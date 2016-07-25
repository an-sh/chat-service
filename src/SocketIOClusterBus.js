
const Promise = require('bluebird')
const _ = require('lodash')
const hasBinary = require('has-binary')
const { EventEmitter } = require('events')

class SocketIOClusterBus extends EventEmitter {

  constructor (server, adapter) {
    super()
    this.server = server
    this.adapter = adapter
    this.channel = 'cluster:bus'
    this.intenalEvents = [ 'roomLeaveSocket',
                           'socketRoomLeft',
                           'disconnectUserSockets' ]
    this.types = [ 2, 5 ]
    this.injectBusHook()
  }

  listen () {
    return Promise.fromCallback(cb => {
      return this.adapter.add(this.server.instanceUID, this.channel, cb)
    })
  }

  makeSocketRoomLeftName (id, roomName) {
    return `socketRoomLeft:${id}:${roomName}`
  }

  mergeEventName (ev, args) {
    switch (ev) {
      case 'socketRoomLeft':
        let [id, roomName, ...nargs] = args
        let nev = this.makeSocketRoomLeftName(id, roomName)
        return [nev, nargs]
      default:
        return [ev, args]
    }
  }

  // TODO: Use an API from socket.io if(when) it will be available.
  emit (ev, ...args) {
    let data = [ ev, ...args ]
    let packet = { type: (hasBinary(args) ? 5 : 2), data }
    let opts = { rooms: [ this.channel ] }
    return this.adapter.broadcast(packet, opts, false)
  }

  onPacket (packet) {
    let [ev, ...args] = packet.data
    if (_.includes(this.intenalEvents, ev)) {
      let [nev, nargs] = this.mergeEventName(ev, args)
      return super.emit(nev, ...nargs)
    } else {
      return super.emit(ev, ...args)
    }
  }

  broadcastHook (packet, opts) {
    let isBusCahnnel = _.indexOf(opts.rooms, this.channel) >= 0
    let isBusType = _.indexOf(this.types, packet.type) >= 0
    if (isBusCahnnel && isBusType) {
      this.onPacket(packet)
    }
  }

  // TODO: Use an API from socket.io if(when) it will be available.
  injectBusHook () {
    let broadcastHook = this.broadcastHook.bind(this)
    let adapter = this.adapter
    let orig = this.adapter.broadcast
    adapter.broadcast = function (...args) {
      broadcastHook(...args)
      orig.apply(adapter, args)
    }
  }

}

module.exports = SocketIOClusterBus
