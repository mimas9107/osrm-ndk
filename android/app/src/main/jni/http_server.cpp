#include "http_server.hpp"

#include <civetweb.h>

#include <osrm/route_parameters.hpp>
#include <osrm/table_parameters.hpp>
#include <osrm/nearest_parameters.hpp>
#include <osrm/trip_parameters.hpp>
#include <osrm/match_parameters.hpp>
#include <osrm/json_container.hpp>
#include <osrm/coordinate.hpp>

#include <util/json_renderer.hpp>

#include <sstream>
#include <cstring>
#include <algorithm>
#include <cstdlib>
#include <map>

// ---------------------------------------------------------------------------
// URL parsing helpers
// ---------------------------------------------------------------------------

static std::string extract_service(const std::string& uri) {
    if (uri.empty() || uri[0] != '/') return {};
    auto slash = uri.find('/', 1);
    if (slash == std::string::npos) return {};
    return uri.substr(1, slash - 1);
}

static std::string extract_query(const std::string& uri) {
    if (uri.empty() || uri[0] != '/') return {};
    int slash_count = 0;
    std::size_t pos = 0;
    for (std::size_t i = 0; i < uri.size(); i++) {
        if (uri[i] == '/') {
            slash_count++;
            if (slash_count == 4) {
                pos = i + 1;
                break;
            }
        }
    }
    if (pos == 0 || pos >= uri.size()) return {};
    return uri.substr(pos);
}

static std::string url_decode(const std::string& src) {
    std::string out;
    out.reserve(src.size());
    for (std::size_t i = 0; i < src.size(); i++) {
        if (src[i] == '%' && i + 2 < src.size()) {
            char hex[3] = {src[i+1], src[i+2], 0};
            out += static_cast<char>(std::strtol(hex, nullptr, 16));
            i += 2;
        } else if (src[i] == '+') {
            out += ' ';
        } else {
            out += src[i];
        }
    }
    return out;
}

static bool parse_coordinates(const std::string& coord_str,
                              std::vector<osrm::util::Coordinate>& coords) {
    std::istringstream stream(coord_str);
    std::string pair;
    while (std::getline(stream, pair, ';')) {
        if (pair.empty()) continue;
        auto comma = pair.find(',');
        if (comma == std::string::npos) return false;
        double lon = std::atof(pair.substr(0, comma).c_str());
        double lat = std::atof(pair.substr(comma + 1).c_str());
        coords.emplace_back(osrm::util::FloatLongitude{lon},
                            osrm::util::FloatLatitude{lat});
    }
    return !coords.empty();
}

static void parse_options(const std::string& opt_str,
                          std::map<std::string, std::string>& opts) {
    std::string s = opt_str;
    if (!s.empty() && s[0] == '?') s = s.substr(1);
    std::istringstream stream(s);
    std::string pair;
    while (std::getline(stream, pair, '&')) {
        if (pair.empty()) continue;
        auto eq = pair.find('=');
        if (eq == std::string::npos) continue;
        opts[url_decode(pair.substr(0, eq))] = url_decode(pair.substr(eq + 1));
    }
}

static bool opt_bool(const std::map<std::string, std::string>& opts,
                      const std::string& key, bool default_val) {
    auto it = opts.find(key);
    return it == opts.end() ? default_val : it->second == "true";
}

template <typename E>
static E opt_enum(const std::map<std::string, std::string>& opts,
                   const std::string& key, E default_val,
                   const std::map<std::string, E>& mapping) {
    auto it = opts.find(key);
    if (it == opts.end()) return default_val;
    auto mi = mapping.find(it->second);
    return mi != mapping.end() ? mi->second : default_val;
}

struct ParsedQuery {
    std::string coords_str;
    std::map<std::string, std::string> options;
};

static ParsedQuery split_query(const std::string& raw) {
    ParsedQuery pq;
    auto qmark = raw.find('?');
    if (qmark == std::string::npos) {
        pq.coords_str = raw;
    } else {
        pq.coords_str = raw.substr(0, qmark);
        parse_options(raw.substr(qmark), pq.options);
    }
    return pq;
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

static void send_json(struct mg_connection* conn, int status, const std::string& json) {
    mg_printf(conn,
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: application/json\r\n"
        "Access-Control-Allow-Origin: *\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n\r\n%s",
        status,
        status == 200 ? "OK" : status == 400 ? "Bad Request"
                  : status == 404 ? "Not Found" : "Error",
        json.size(), json.c_str());
}

static void send_error(struct mg_connection* conn, int status,
                        const std::string& code, const std::string& message) {
    std::string json = "{\"code\":\"" + code + "\",\"message\":\"" + message + "\"}";
    send_json(conn, status, json);
}

// ---------------------------------------------------------------------------
// Civetweb callback (1-arg signature for civetweb 1.15)
// ---------------------------------------------------------------------------

static int route_handler(struct mg_connection* conn) {
    const struct mg_request_info* ri = mg_get_request_info(conn);
    if (!ri || !ri->user_data) {
        send_error(conn, 503, "ServiceUnavailable", "OSRM engine not initialized");
        return 200;
    }

    auto* server = static_cast<HttpServer*>(ri->user_data);
    if (!server || !server->engine()) {
        send_error(conn, 503, "ServiceUnavailable", "OSRM engine not initialized");
        return 200;
    }

    std::string uri = ri->local_uri_raw ? ri->local_uri_raw : (ri->local_uri ? ri->local_uri : "/");

    if (uri == "/" || uri == "/health") {
        send_json(conn, 200, "{\"status\":\"healthy\"}");
        return 200;
    }

    std::string service = extract_service(uri);
    if (service.empty()) {
        send_error(conn, 404, "NotFound", "Invalid URL format");
        return 200;
    }

    std::string raw_query = extract_query(uri);
    if (raw_query.empty()) {
        send_error(conn, 400, "InvalidQuery", "Missing coordinates");
        return 200;
    }

    ParsedQuery pq = split_query(raw_query);

    std::vector<osrm::util::Coordinate> coords;
    if (!parse_coordinates(pq.coords_str, coords)) {
        send_error(conn, 400, "InvalidQuery", "Failed to parse coordinates");
        return 200;
    }

    const std::map<std::string, osrm::RouteParameters::GeometriesType> geom_map = {
        {"polyline", osrm::RouteParameters::GeometriesType::Polyline},
        {"polyline6", osrm::RouteParameters::GeometriesType::Polyline6},
        {"geojson", osrm::RouteParameters::GeometriesType::GeoJSON},
    };
    const std::map<std::string, osrm::RouteParameters::OverviewType> overview_map = {
        {"simplified", osrm::RouteParameters::OverviewType::Simplified},
        {"full", osrm::RouteParameters::OverviewType::Full},
        {"false", osrm::RouteParameters::OverviewType::False},
    };

    osrm::util::json::Object json_result;

    if (service == "route") {
        osrm::RouteParameters params;
        params.coordinates = coords;
        params.steps = opt_bool(pq.options, "steps", false);
        params.alternatives = opt_bool(pq.options, "alternatives", false);
        params.annotations = opt_bool(pq.options, "annotations", false);
        params.geometries = opt_enum(pq.options, "geometries",
            osrm::RouteParameters::GeometriesType::Polyline, geom_map);
        params.overview = opt_enum(pq.options, "overview",
            osrm::RouteParameters::OverviewType::Simplified, overview_map);
        params.generate_hints = false;
        params.skip_waypoints = true;

        if (!params.IsValid()) {
            send_error(conn, 400, "InvalidOptions", "Need at least 2 coordinates");
            return 200;
        }

        std::string body;
        auto status = server->engine()->Route(params, json_result);
        osrm::util::json::render(body, json_result);
        send_json(conn, status == osrm::Status::Ok ? 200 : 400, body);

    } else if (service == "trip") {
        osrm::TripParameters params;
        params.coordinates = coords;
        params.steps = opt_bool(pq.options, "steps", false);
        params.geometries = opt_enum(pq.options, "geometries",
            osrm::TripParameters::GeometriesType::Polyline, geom_map);
        params.overview = opt_enum(pq.options, "overview",
            osrm::TripParameters::OverviewType::Simplified, overview_map);
        params.roundtrip = opt_bool(pq.options, "roundtrip", true);
        params.generate_hints = false;
        params.skip_waypoints = true;

        std::string body;
        auto status = server->engine()->Trip(params, json_result);
        osrm::util::json::render(body, json_result);
        send_json(conn, status == osrm::Status::Ok ? 200 : 400, body);

    } else if (service == "table") {
        osrm::TableParameters params;
        params.coordinates = coords;
        params.generate_hints = false;
        params.skip_waypoints = true;

        std::string body;
        auto status = server->engine()->Table(params, json_result);
        osrm::util::json::render(body, json_result);
        send_json(conn, status == osrm::Status::Ok ? 200 : 400, body);

    } else if (service == "nearest") {
        osrm::NearestParameters params;
        params.coordinates = coords;
        params.number_of_results = 1;
        params.generate_hints = false;
        params.skip_waypoints = true;

        std::string body;
        auto status = server->engine()->Nearest(params, json_result);
        osrm::util::json::render(body, json_result);
        send_json(conn, status == osrm::Status::Ok ? 200 : 400, body);

    } else if (service == "match") {
        osrm::MatchParameters params;
        params.coordinates = coords;
        params.steps = opt_bool(pq.options, "steps", false);
        params.geometries = opt_enum(pq.options, "geometries",
            osrm::MatchParameters::GeometriesType::Polyline, geom_map);
        params.overview = opt_enum(pq.options, "overview",
            osrm::MatchParameters::OverviewType::Simplified, overview_map);
        params.generate_hints = false;
        params.skip_waypoints = true;

        std::string body;
        auto status = server->engine()->Match(params, json_result);
        osrm::util::json::render(body, json_result);
        send_json(conn, status == osrm::Status::Ok ? 200 : 400, body);

    } else {
        send_error(conn, 404, "NotFound", "Unknown service: " + service);
    }

    return 200;
}

// ---------------------------------------------------------------------------
// HttpServer implementation
// ---------------------------------------------------------------------------

HttpServer::HttpServer(const std::string& data_path, int port)
    : data_path_(data_path), port_(port) {}

HttpServer::~HttpServer() { stop(); }

bool HttpServer::start() {
    osrm::EngineConfig config;
    config.storage_config = {data_path_};
    config.use_shared_memory = false;
    config.algorithm = osrm::EngineConfig::Algorithm::MLD;

    engine_ = std::make_unique<osrm::OSRM>(config);

    std::string port_str = std::to_string(port_);
    const char* opts[] = {
        "listening_ports", port_str.c_str(),
        "document_root", ".",
        "access_control_allow_origin", "*",
        "num_threads", "4",
        "request_timeout_ms", "30000",
        nullptr
    };

    struct mg_callbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.begin_request = route_handler;

    ctx_ = mg_start(&callbacks, this, opts);
    if (!ctx_) {
        engine_.reset();
        return false;
    }

    running_ = true;
    return true;
}

void HttpServer::stop() {
    running_ = false;
    if (ctx_) {
        mg_stop(ctx_);
        ctx_ = nullptr;
    }
    engine_.reset();
}

bool HttpServer::is_running() const { return running_; }
