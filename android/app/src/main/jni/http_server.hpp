#ifndef OSRM_HTTP_SERVER_H
#define OSRM_HTTP_SERVER_H

#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <memory>

#include <osrm/osrm.hpp>
#include <osrm/engine_config.hpp>
#include <osrm/status.hpp>

struct mg_context;

class HttpServer {
public:
    HttpServer(const std::string& data_path, int port);
    ~HttpServer();

    bool start();
    void stop();
    bool is_running() const;

    osrm::OSRM* engine() { return engine_.get(); }

private:
    static int handle_request(struct mg_connection* conn, void* cbdata);

    std::unique_ptr<osrm::OSRM> engine_;
    struct mg_context* ctx_ = nullptr;
    std::string data_path_;
    int port_;
    std::atomic<bool> running_{false};
};

#endif // OSRM_HTTP_SERVER_H
