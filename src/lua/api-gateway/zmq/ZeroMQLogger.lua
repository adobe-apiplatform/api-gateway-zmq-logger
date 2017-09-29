-- Copyright 2015 Adobe Systems Incorporated. All rights reserved.
--
-- This file is licensed to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.

--
-- Logs all messages to a ZeroMQ queue
-- Usage:
-- init_worker_by_lua '
--        local ZmqLogger = require "api-gateway.zmq.ZeroMQLogger"
--        if not ngx.zmqLogger then
--            ngx.log(ngx.INFO, "Starting new ZmqLogger .. ")
--            ngx.zmqLogger = ZmqLogger:new()
--            ngx.zmqLogger:connect(ZmqLogger.SOCKET_TYPE.ZMQ_PUB, "ipc:///tmp/xsub")
--        end
--    ';
--

local setmetatable = setmetatable
local error = error
local ffi = require "ffi"
local ffi_new = ffi.new
local ffi_str = ffi.string
local C = ffi.C
local zmqlib = ffi.load("zmq")
local czmq = ffi.load("czmq")

local SOCKET_TYPE = {
    ZMQ_PAIR = 0,
    ZMQ_PUB = 1,
    ZMQ_SUB = 2,
    ZMQ_REQ = 3,
    ZMQ_REP = 4,
    ZMQ_DEALER = 5,
    ZMQ_ROUTER = 6,
    ZMQ_PULL = 7,
    ZMQ_PUSH = 8,
    ZMQ_XPUB = 9,
    ZMQ_XSUB = 10,
    ZMQ_STREAM = 11
}

local _M = { _VERSION = '0.1' }
local mt = { __index = _M }
_M.SOCKET_TYPE = SOCKET_TYPE

ffi.cdef [[
    typedef struct _zctx_t zctx_t;
    extern volatile int zctx_interrupted;
    zctx_t * zctx_new (void);
    void * zsocket_new (zctx_t *self, int type);
    int zsocket_connect (void *socket, const char *format, ...);
    int zsocket_bind (void *socket, const char *format, ...);

    void zctx_destroy (zctx_t **self_p);
    void zsocket_destroy (zctx_t *self, void *socket);

    void zsocket_set_subscribe (void *zocket, const char * subscribe);
    int zstr_send (void *socket, const char *string);

    int zmq_ctx_destroy (void *context);

    void zmq_version (int *major, int *minor, int *patch);
]]


local ctx_v = czmq.zctx_new()
local ctx = ffi_new("zctx_t *", ctx_v)
local socketInst

local check_worker_delay = 5
local function check_worker_process(premature)
    if not premature then
        local ok, err = ngx.timer.at(check_worker_delay, check_worker_process)
        if not ok then
            ngx.log(ngx.ERR, "failed to create timer to check worker process: ", err)
        end
    else
        ngx.log(ngx.INFO, "Terminating ZMQ context due to worker termination ...")
        -- this should be called when the worker is stopped
        zmqlib.zmq_ctx_destroy(ctx)
    end
end

local ok, err = ngx.timer.at(check_worker_delay, check_worker_process)
if not ok then
    ngx.log(ngx.ERR, "failed to create timer to check worker process: ", err)
end

function _M.new(self)
    return setmetatable({}, mt)
end

function _M.connect(self, socket_type, socket_address)
    if (socket_type == nil) then
        error("Socket type must be provided.")
    end

    if (socket_address == nil) then
        error("Socket address must be provided.")
    end

    local intPtr = ffi.typeof("int[1]")
    local zmq_version_major_holder = intPtr()
    local zmq_version_minor_holder = intPtr()
    local zmq_version_patch_holder = intPtr()

    czmq.zmq_version(zmq_version_major_holder, zmq_version_minor_holder, zmq_version_patch_holder)

    -- Dereference the pointers
    --noinspection ArrayElementZero
    local major = tostring(zmq_version_major_holder[0]);
    --noinspection ArrayElementZero
    local minor = tostring(zmq_version_minor_holder[0]);
    --noinspection ArrayElementZero
    local patch = tostring(zmq_version_patch_holder[0]);

    ngx.log(ngx.INFO, "Using ZeroMQ ", major, ".", minor, ".", patch)

    self.socketInst = czmq.zsocket_new(ctx, socket_type)

    local ngx_worker_pid_msg = "worker pid=" .. tostring(ngx.worker.pid())
    local socket_address_msg = "socket_address=" .. socket_address
    local pid_and_address_msg = ngx_worker_pid_msg .. ", " .. socket_address_msg

    if (self.socketInst == nil) then
        error("Socket could not be created; " .. pid_and_address_msg)
    end

    local zsocket_connect_result = czmq.zsocket_connect(self.socketInst, socket_address)
    local zsocket_connect_result_msg = "zsocket_connect result=" .. tostring(zsocket_connect_result)
    local pid_and_result_msg = ngx_worker_pid_msg .. ", " .. zsocket_connect_result_msg

    if (zsocket_connect_result == 0) then
        ngx.log(ngx.INFO, "Connected socket; ", pid_and_result_msg)
    elseif (zsocket_connect_result == -1) then
        ngx.log(ngx.ERR, "Could not connect socket; ", pid_and_result_msg)
    else
        error("Unexpected result while attempting to connect to [" .. socket_address_msg .. "]; " .. pid_and_result_msg)
    end
end

function _M.log(self, msg)
    local ngx_worker_pid_msg = "worker pid=" .. tostring(ngx.worker.pid())

    if (msg == nil or #msg == 0) then
        ngx.log(ngx.WARN, "Nothing to send; ", ngx_worker_pid_msg)
        return
    end

    local zstr_send_result = czmq.zstr_send(self.socketInst, msg)
    local zstr_send_result_msg = "zstr_send result=" .. tostring(zstr_send_result)
    local pid_and_result_msg = ngx_worker_pid_msg .. ", " .. zstr_send_result_msg

    if (zstr_send_result == 0) then
        ngx.log(ngx.DEBUG, "Message [", msg, "] has been sent; ", pid_and_result_msg)
    elseif (zstr_send_result == -1) then
        ngx.log(ngx.ERR, "Message [", msg, "] could not be sent; ", pid_and_result_msg)
    else
        error("Unexpected result while attempting to send message [" .. msg .. "]; " .. pid_and_result_msg)
    end
end

function _M.disconnect(self)
    --czmq.zsocket_destroy(ctx, self.socketInst)
    zmqlib.zmq_ctx_destroy(ctx)
end


-- wait for the connection to complete then send the message, otherwise it is not received
--ngx.sleep(0.100)

return _M
