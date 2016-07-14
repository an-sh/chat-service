
import ChatServiceError from './ChatServiceError';
import { EventEmitter } from 'events';
import Promise from 'bluebird';
import RedisAdapter from 'socket.io-redis';
import SocketServer from 'socket.io';
import Transport from './Transport';
import _ from 'lodash';
import hasBinary from 'has-binary';

import { debuglog, execHook, checkNameSymbols } from './utils';


// @private
// @nodoc
// Cluster bus.
class ClusterBus extends EventEmitter {

  // @private
  constructor(server, adapter) {
    super();
    this.server = server;
    this.adapter = adapter;
    this.channel = 'cluster:bus';
    this.intenalEvents = ['roomLeaveSocket', 'socketRoomLeft'
      , 'disconnectUserSockets'];
    this.types = [ 2, 5 ];
  }

  // @private
  listen() {
    return Promise.fromCallback(cb => {
      return this.adapter.add(this.server.instanceUID, this.channel, cb);
    }
    );
  }

  // @private
  makeSocketRoomLeftName(id, roomName) {
    return `socketRoomLeft:${id}:${roomName}`;
  }

  // @private
  mergeEventName(ev, args) {
    switch (ev) {
      case 'socketRoomLeft':
        let [ id, roomName, ...nargs ] = args;
        let nev = this.makeSocketRoomLeftName(id, roomName);
        return [nev, nargs];
      default:
        return [ev, args];
    }
  }

  // @private
  // TODO: Use an API from socket.io if(when) it will be available.
  emit(ev, ...args) {
    let data = [ ev, ...args ];
    let packet = { type : (hasBinary(args) ? 5 : 2)
    , data
  };
    let opts = {rooms : [ this.channel ]};
    return this.adapter.broadcast(packet, opts, false);
  }

  // @private
  onPacket(packet) {
    let [ev, ...args] = packet.data;
    if (_.includes(this.intenalEvents, ev)) {
      let [nev, nargs] = this.mergeEventName(ev, args);
      return super.emit(nev, ...nargs);
    } else {
      return super.emit(ev, ...args); //bug decaffeinate 2.16.0
    }
  }
}


// @private
// @nodoc
// Socket.io transport.
class SocketIOTransport extends Transport {

  // @private
  constructor(server, options, adapterConstructor, adapterOptions) {
    super();
    this.server = server;
    this.options = options;
    this.adapterConstructor = adapterConstructor;
    this.adapterOptions = adapterOptions;
    this.hooks = this.server.hooks;
    this.io = this.options.io;
    this.namespace = this.options.namespace || '/chat-service';
    let Adapter = (() => { switch (true) {
      case this.adapterConstructor === 'memory': return null;
      case this.adapterConstructor === 'redis': return RedisAdapter;
      case _.isFunction(this.adapterConstructor): return this.adapterConstructor;
      default: throw new Error(`Invalid transport adapter: ${this.adapterConstructor}`);
    } })();
    if (!this.io) {
      this.ioOptions = this.options.ioOptions;
      this.http = this.options.http;
      if (this.http) {
        this.dontCloseIO = true;
        this.io = new SocketServer(this.options.http);
      } else {
        //bug decaffeinate 2.16.0
        this.io = new SocketServer(this.server.port, this.ioOptions);
      }
      if (Adapter) {
        this.adapter = new Adapter(...this.adapterOptions);
        this.io.adapter(this.adapter);
      }
    } else {
      this.dontCloseIO = true;
    }
    this.nsp = this.io.of(this.namespace);
    this.server.io = this.io;
    this.server.nsp = this.nsp;
    this.clusterBus = new ClusterBus(this.server, this.nsp.adapter);
    this.injectBusHook();
    this.attachBusListeners();
    this.server.clusterBus = this.clusterBus;
    this.closed = false;
  }

  // @private
  broadcastHook(packet, opts) {
    if( _.indexOf(opts.rooms, this.clusterBus.channel) >= 0 &&
    _.indexOf(this.clusterBus.types, packet.type) >= 0 ) {
      return this.clusterBus.onPacket(packet);
    }
  }

  // @private
  // TODO: Use an API from socket.io if(when) it will be available.
  injectBusHook() {
    let broadcastHook = this.broadcastHook.bind(this);
    let { adapter } = this.nsp;
    let orig = adapter.broadcast;
    return adapter.broadcast = function(...args) {
      broadcastHook(...args);
      return orig.apply(adapter, args);
    };
  }

  // @private
  attachBusListeners() {
    this.clusterBus.on('roomLeaveSocket', (id, roomName) => {
      return this.leaveChannel(id, roomName)
      .then(() => {
        return this.clusterBus.emit('socketRoomLeft', id, roomName);
      }
      )
      .catchReturn();
    }
    );
    return this.clusterBus.on('disconnectUserSockets', userName => {
      return this.server.state.getUser(userName)
      .then(user => user.disconnectInstanceSockets())
      .catchReturn();
    }
    );
  }

  // @private
  rejectLogin(socket, error) {
    let { useRawErrorObjects } = this.server;
    if ((error != null) && !(error instanceof ChatServiceError)) {
      debuglog(error);
    }
    if ((error != null) && !useRawErrorObjects) {
      error = error.toString();
    }
    socket.emit('loginRejected', error);
    return socket.disconnect();
  }

  // @private
  confirmLogin(socket, userName, authData) {
    authData.id = socket.id;
    socket.emit('loginConfirmed', userName, authData);
    return Promise.resolve();
  }

  // @private
  addClient(socket, userName, authData = {}) {
    let { id } = socket;
    return Promise.try(function() {
      if (!userName) {
        let { query } = socket.handshake;
        userName = query && query.user;
        if (!userName) {
          return Promise.reject(new ChatServiceError('noLogin'));
        }
      }
    })
    .then(() => checkNameSymbols(userName))
    .then(() => {
      return this.server.state.getOrAddUser(userName);
    }
    )
    .then(user => user.registerSocket(id))
    .spread((user, nconnected) => {
      return this.joinChannel(id, user.echoChannel)
      .then(() => {
        user.socketConnectEcho(id, nconnected);
        return this.confirmLogin(socket, userName, authData);
      }
      );
    }
    )
    .catch(error => {
      return this.rejectLogin(socket, error);
    }
    );
  }

  // @private
  setEvents() {
    if (this.hooks.middleware) {
      let middleware = _.castArray(this.hooks.middleware);
      for (let i = 0; i < middleware.length; i++) {
        let fn = middleware[i];
        this.nsp.use(fn);
      }
    }
    if (this.hooks.onConnect) {
      this.nsp.on('connection', socket => {
        return Promise.try(() => {
          return execHook(this.hooks.onConnect, this.server, socket.id);
        }
        )
        .then(loginData => {
          loginData = _.castArray(loginData);
          return this.addClient(socket, ...loginData);
        }
        )
        .catch(error => {
          return this.rejectLogin(socket, error);
        }
        );
      }
      );
    } else {
      this.nsp.on('connection', this.addClient.bind(this)); //bug decaffeinate 2.16.0
    }
    return Promise.resolve();
  }

  // @private
  waitCommands() {
    if (this.server.runningCommands > 0) {
      return Promise.fromCallback(cb => {
        return this.server.once('commandsFinished', cb);
      }
      );
    }
  }

  // @private
  close() {
    this.closed = true;
    this.nsp.removeAllListeners('connection');
    this.clusterBus.removeAllListeners();
    return Promise.try(() => {
      if (!this.dontCloseIO) {
        this.io.close();
      } else if (this.http) {
        this.io.engine.close();
      } else {
        for (let id in this.nsp.connected) {
          let socket = this.nsp.connected[id];
          socket.disconnect();
        }
      }
    }
    )
    .then(() => {
      return this.waitCommands();
    }
    )
    .timeout(this.server.closeTimeout);
  }

  // @private
  bindHandler(id, name, fn) {
    let socket = this.getConnectionObject(id);
    if (socket) {
      return socket.on(name, fn);
    }
  }

  // @private
  getConnectionObject(id) {
    // super.getConnectionObject();
    return this.nsp.connected[id];
  }

  // @private
  emitToChannel(channel, messageName, ...messageData) {
    // super.emitToChannel();
    this.nsp.to(channel).emit(messageName, ...messageData);
  }

  // @private
  sendToChannel(id, channel, messageName, ...messageData) {
    // super.sendToChannel();
    let socket = this.getConnectionObject(id);
    if (!socket) {
      this.emitToChannel(channel, messageName, ...messageData);
    } else {
      //bug decaffeinate 2.16.0
      socket.to(channel).emit(messageName, ...messageData);
    }
  }

  // @private
  joinChannel(id, channel) {
    let socket = this.getConnectionObject(id);
    if (!socket) {
      return Promise.reject(new ChatServiceError('invalidSocket', id));
    } else {
      //bug decaffeinate 2.16.0
      return Promise.fromCallback( fn => socket.join(channel, fn));
    }
  }

  // @private
  leaveChannel(id, channel) {
    let socket = this.getConnectionObject(id);
    if (!socket) { return Promise.resolve(); }
    return Promise.fromCallback(fn => socket.leave(channel, fn));
  }

  // @private
  disconnectClient(id) {
    let socket = this.getConnectionObject(id);
    if (socket) {
      socket.disconnect();
    }
    return Promise.resolve();
  }
}


export default SocketIOTransport;
