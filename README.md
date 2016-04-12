# api-gateway-zmq-logger
Lua logger to send ZMQ messages using `czmq` lib, via Lua FFI.

Table of Contents
=================

* [Status](#status)
* [Dependencies](#dependencies)
* [Sample Usage](#sample-usage)
* [Developer Guide](#developer-guide)

Status
======
This module is under active development and is considered production ready.

Dependencies
============

This library requires an nginx build,
the [ngx_lua module](http://wiki.nginx.org/HttpLuaModule), [LuaJIT 2.0](http://luajit.org/luajit.html),
[api-gateway-zmq-adaptor](https://github.com/adobe-apiplatform/api-gateway-zmq-adaptor) and
[czmq](http://czmq.zeromq.org/)


Sample usage
============

```nginx

    http {
        # lua_package_path should point to the location on the disk where the "scripts" folder is located
        lua_package_path "scripts/?.lua;/src/lua/api-gateway?.lua;;";

        #
        # initialize the zmqLogger for each worker process
        #
        init_worker_by_lua '
            ngx.apiGateway = ngx.apiGateway or {}

            local ZmqLogger = require "api-gateway.zmq.ZeroMQLogger"
            local zmq_publish_address = "ipc:///tmp/nginx_queue_listen"
            ngx.log(ngx.INFO, "Starting new ZmqLogger on pid [", tostring(ngx.worker.pid()), "] on address [", zmq_publish_address, "]")

            -- create a new ZMQ PUB socket
            local zmqLogger = ZmqLogger:new()
            zmqLogger:connect(ZmqLogger.SOCKET_TYPE.ZMQ_PUB, zmq_publish_address)

            ngx.apiGateway.zmqLogger = zmqLogger
         ';
    }

    server {

        location /sample-logging-location {
            ...
            log_by_lua '
                if ( ngx.apiGateway.logger.zmq ~= nil ) then
                    ngx.apiGateway.logger.zmq.log("hello-world")
                end
            ';
    }

```

Developer guide
===============

## Running the tests

### With docker

```
make test-docker
```
This command spins up 2 containers ( Redis and API Gateway ) and executes the tests in `test/perl`
