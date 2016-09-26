'use strict'

const ExecInfo = require('./ExecInfo')
const Promise = require('bluebird')
const _ = require('lodash')
const { execHook, logError, possiblyCallback, resultsTransform } =
        require('./utils')

const co = Promise.coroutine

// Implements command functions binding and wrapping.
class CommandBinder {

  constructor (server, transport, userName) {
    this.server = server
    this.transport = transport
    this.userName = userName
  }

  commandWatcher (id, name) {
    this.server.runningCommands++
    return Promise.resolve().disposer(() => {
      this.server.runningCommands--
      if (this.transport.closed && this.server.runningCommands <= 0) {
        this.server.emit('commandsFinished')
      }
    })
  }

  makeCommand (name, fn) {
    let { validator } = this.server
    let beforeHook = this.server.hooks[`${name}Before`]
    let afterHook = this.server.hooks[`${name}After`]
    return (args, info) => {
      let execInfo = new ExecInfo()
      let context = { server: this.server, userName: this.userName }
      let argsInfo = validator.splitArguments(name, args)
      _.assign(execInfo, context, info, argsInfo)
      return Promise.using(this.commandWatcher(info.id, name), co(function * () {
        yield validator.checkArguments(name, ...execInfo.args)
        let results
        if (beforeHook && !execInfo.bypassHooks) {
          results = yield execHook(beforeHook, execInfo)
        }
        if (results && results.length) { return results }
        yield fn(...execInfo.args, execInfo)
          .then(result => { execInfo.results = [result] })
          .catch(error => { execInfo.error = error })
        if (afterHook && !execInfo.bypassHooks) {
          results = yield execHook(afterHook, execInfo)
        }
        if (results && results.length) {
          return results
        } else if (execInfo.error) {
          return Promise.reject(execInfo.error)
        } else {
          return execInfo.results
        }
      })).catch(logError)
    }
  }

  bindDisconnect (id, fn) {
    let server = this.server
    let hook = this.server.hooks.onDisconnect
    this.transport.bindHandler(id, 'disconnect', () => {
      return Promise.using(
        this.commandWatcher(id, 'disconnect'),
        () => fn(id)
          .catch(logError)
          .catchReturn()
          .then(data => execHook(hook, server, _.assign({id}, data)))
          .catch(logError)
          .catchReturn())
    })
  }

  bindCommand (id, name, fn) {
    let cmd = this.makeCommand(name, fn)
    let useErrorObjects = this.server.useRawErrorObjects
    let info = {id}
    return this.transport.bindHandler(id, name, function () {
      let [args, cb] = possiblyCallback(arguments)
      let ack = resultsTransform(useErrorObjects, cb)
      return cmd(args, info).asCallback(ack, { spread: true })
    })
  }

}

module.exports = CommandBinder
