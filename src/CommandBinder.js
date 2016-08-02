
const ExecInfo = require('./ExecInfo')
const Promise = require('bluebird')
const _ = require('lodash')
const { convertError, execHook, possiblyCallback, transformResults } =
        require('./utils')

// Implements command implementation functions binding and wrapping.
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
    let useErrorObjects = this.server.useRawErrorObjects
    return (args, info) => {
      let execInfo = new ExecInfo()
      _.assign(execInfo, { server: this.server, userName: this.userName })
      _.assign(execInfo, info)
      _.assign(execInfo, validator.splitArguments(name, args))
      return Promise.using(
        this.commandWatcher(info.id, name),
        () => validator.checkArguments(name, ...execInfo.args)
          .then(() => {
            if (beforeHook && !execInfo.bypassHooks) {
              return execHook(beforeHook, execInfo)
            } else {
              return Promise.resolve()
            } })
          .then(results => {
            if (results && results.length) { return results }
            return fn(...execInfo.args, execInfo)
              .then(result => { execInfo.results = [result] },
                    error => { execInfo.error = error })
              .then(() => {
                if (afterHook && !execInfo.bypassHooks) {
                  return execHook(afterHook, execInfo)
                } else {
                  return Promise.resolve()
                } })
              .then(results => {
                if (results && results.length) {
                  return results
                } else if (execInfo.error) {
                  return Promise.reject(execInfo.error)
                } else {
                  return execInfo.results
                }
              })
          }))
        .catch(error => Promise.reject(convertError(error, useErrorObjects)))
    }
  }

  bindDisconnect (id, fn) {
    let server = this.server
    let hook = this.server.hooks.onDisconnect
    this.transport.bindHandler(id, 'disconnect', () => {
      return Promise.using(
        this.commandWatcher(id, 'disconnect'),
        () => fn(id).then(() => execHook(hook, server, id)).catchReturn())
    })
  }

  bindCommand (id, name, fn) {
    let cmd = this.makeCommand(name, fn)
    let info = {id}
    return this.transport.bindHandler(id, name, function () {
      let [args, cb] = possiblyCallback(arguments)
      let ack = transformResults(cb)
      return cmd(args, info).asCallback(ack, { spread: true })
    })
  }

}

module.exports = CommandBinder
