'use strict'

const Promise = require('bluebird')
const { EventEmitter } = require('events')
const eventToPromise = require('event-to-promise')

// Instances communication via a socket.io redis adapter.
class SocketIOClusterBus extends EventEmitter {
  constructor (server, transport) {
    super()
    this.server = server
    this.transport = transport
    this.adapter = this.transport.nsp.adapter
    this.marker = 'cluster-bus'
    this.adapter.customHook = this.customHook.bind(this)
  }

  listen () {
    if (this.adapter.subClient) {
      if (this.adapter.subClient.connected) {
        return Promise.resolve()
      } else {
        return Promise.all([
          eventToPromise(this.adapter.subClient, 'psubscribe'),
          eventToPromise(this.adapter.subClient, 'subscribe')
        ])
      }
    } else {
      return Promise.resolve()
    }
  }

  emit (ev, ...args) {
    if (this.adapter.customRequest) {
      const data = {
        marker: this.marker,
        ev,
        args
      }
      this.adapter.customRequest(data)
    } else {
      super.emit(ev, ...args)
    }
  }

  customHook (data, cb) {
    try {
      if (data.marker === this.marker) {
        const { ev, args } = data
        super.emit(ev, ...args)
      }
      cb()
    } catch (e) {
      cb(e)
    }
  }
}

module.exports = SocketIOClusterBus
