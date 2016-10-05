'use strict'

const Promise = require('bluebird')
const _ = require('lodash')
const { EventEmitter } = require('events')
const { mergeEventName } = require('./utils')

// from socket.io-protocol v4
const EVENT = 2
const BINARY_EVENT = 5

// Instances communication via a socket.io-adapter implementation.
class SocketIOClusterBus extends EventEmitter {

  constructor (server, transport) {
    super()
    this.server = server
    this.transport = transport
    this.adapter = this.transport.nsp.adapter
    this.channel = 'cluster:bus'
    this.types = [ EVENT, BINARY_EVENT ]
    this.injectBusHook()
  }

  listen () {
    return Promise.fromCallback(cb => {
      this.adapter.add(this.server.instanceUID, this.channel, cb)
    })
  }

  emit (ev, ...args) {
    this.transport.emitToChannel(this.channel, ev, ...args)
  }

  onPacket (packet) {
    let [ev, ...args] = packet.data
    let [nev, nargs] = mergeEventName(ev, args)
    super.emit(nev, ...nargs)
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
