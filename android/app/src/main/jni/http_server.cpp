#include "http_server.hpp"

#include <civetweb.h>
#include <sstream>
#include <fstream>
#include <cstring>
#include <algorithm>

#include <osrm/route_parameters.hpp>
#include <osrm/json_container.hpp>

#include <engine/api/flatbuffers/fbresult_generated.h>

// ---------------------------------------------------------------------------
// Civetweb callbacks
// ---------------------------------------------------------------------------

static int route_handler(struct mg_connection* conn, void* cbdata) {
    auto* server = static_cast<HttpServer*>(cbdata);
    if (!server || !server->engine()) {
        mg_printf(conn,
            "HTTP/1.1 503 Service Unavailable\r\n"
            "Content-Type: text/plain\r\n\r\n"
            "OSRM engine not initialized");
        return 200;
    }

    // Read request URI
    const struct mg_request_info* ri = mg_get_request_info(conn);
    std::string uri = ri ? ri->local_uri_raw ? ri->local_uri_raw : ri->local_uri : "/";
    std::string qs  = ri ? ri->query_string ? ri->query_string : "" : "";

    // Build full query
    std::string full_query = uri;
    if (!qs.empty()) full_query += "?" + qs;

    // Only handle /route and /trip for now
    if (uri.find("/route") == 0 || uri.find("/trip") == 0 || uri.find("/table") == 0) {
        // Parse query string into RouteParameters
        osrm::RouteParameters params;
        bool parse_ok = params.set_from_query(full_query);

        if (!parse_ok) {
            mg_printf(conn,
                "HTTP/1.1 400 Bad Request\r\n"
                "Content-Type: application/json\r\n\r\n"
                R"({"code":"InvalidQuery","message":"Failed to parse query"})");
            return 200;
        }

        // Execute routing
        osrm::engine::api::ResultT result = osrm::engine::api::FlatbuffersFormat();
        osrm::Status stat;

        if (uri.find("/trip") == 0) {
            stat = server->engine()->Trip(params, result);
        } else if (uri.find("/table") == 0) {
            stat = server->engine()->Table(params, result);
        } else {
            stat = server->engine()->Route(params, result);
        }

        if (stat == osrm::Status::Ok) {
            auto& fb_result = std::get<osrm::engine::api::FlatbuffersFormat>(result);
            std::string json = fb_result.ToJson().dump();

            mg_printf(conn,
                "HTTP/1.1 200 OK\r\n"
                "Content-Type: application/json\r\n"
                "Access-Control-Allow-Origin: *\r\n"
                "Content-Length: %zu\r\n\r\n%s",
                json.size(), json.c_str());
        } else {
            auto& fb_result = std::get<osrm::engine::api::FlatbuffersFormat>(result);
            std::string json = fb_result.ToJson().dump();

            mg_printf(conn,
                "HTTP/1.1 400 Bad Request\r\n"
                "Content-Type: application/json\r\n"
                "Access-Control-Allow-Origin: *\r\n"
                "Content-Length: %zu\r\n\r\n%s",
                json.size(), json.c_str());
        }
    } else {
        mg_printf(conn,
            "HTTP/1.1 404 Not Found\r\n"
            "Content-Type: application/json\r\n\r\n"
            R"({"code":"NotFound","message":"Endpoint not found"})");
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
    // Initialize OSRM engine
    osrm::EngineConfig config;
    config.storage_config = {data_path_};
    config.use_shared_memory = false;
    config.algorithm = osrm::Algorithm::MLD;

    engine_ = std::make_unique<osrm::OSRM>(config);

    // Start civetweb
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
