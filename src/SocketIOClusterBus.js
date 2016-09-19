'use strict'

const Promise = require('bluebird')
const _ = require('lodash')
const hasBinary = require('has-binary')
const { EventEmitter } = require('events')

// from socket.io-protocol v4
const EVENT = 2
const BINARY_EVENT = 5

// Instances communication via a socket.io-adapter implementation.
class SocketIOClusterBus extends EventEmitter {

  constructor (server, adapter) {
    super()
    this.server = server
    this.adapter = adapter
    this.channel = 'cluster:bus'
    this.intenalEvents = [ 'roomLeaveSocket',
                           'socketRoomLeft',
                           'disconnectUserSockets' ]
    this.types = [ EVENT, BINARY_EVENT ]
    this.injectBusHook()
  }

  listen () {
    return Promise.fromCallback(cb => {
      this.adapter.add(this.server.instanceUID, this.channel, cb)
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
    let packet = { type: (hasBinary(args) ? BINARY_EVENT : EVENT), data }
    let opts = { rooms: [ this.channel ] }
    this.adapter.broadcast(packet, opts, false)
  }

  onPacket (packet) {
    let [ev, ...args] = packet.data
    if (_.includes(this.intenalEvents, ev)) {
      let [nev, nargs] = this.mergeEventName(ev, args)
      super.emit(nev, ...nargs)
    } else {
      super.emit(ev, ...args)
    }
  }

  broadcastHook (packet, opts) {
    let isBusCahnnel = _.includes(opts.rooms, this.channel)
    let isBusType = _.includes(this.types, packet.type)
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
