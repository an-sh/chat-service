
const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const _ = require('lodash')
const util = require('util')

let debuglog = util.debuglog('ChatService')

let asyncLimit = 32

let nameChecker = /^[^\u0000-\u001F:{}\u007F]+$/

function possiblyCallback (args) {
  let cb = _.last(args)
  if (_.isFunction(cb)) {
    args = _.slice(args, 0, -1)
  } else {
    cb = null
  }
  return [args, cb]
}

function checkNameSymbols (name) {
  if (_.isString(name) && nameChecker.test(name)) {
    return Promise.resolve()
  } else {
    return Promise.reject(new ChatServiceError('invalidName', name))
  }
}

function execHook (hook, ...args) {
  if (!hook) { return Promise.resolve() }
  let cb = null
  let callbackData = null
  let wrapper = function (...data) {
    callbackData = data
    if (cb) { cb(...data) }
  }
  let res = hook(...args, wrapper)
  if (callbackData) {
    return Promise.fromCallback(
      fn => { fn(...callbackData) },
      {multiArgs: true})
  } else if ((res != null) && typeof res.then === 'function') {
    return res
  } else {
    return Promise.fromCallback(fn => { cb = fn }, {multiArgs: true})
  }
}

function run (self, gen) {
  return Promise.coroutine(gen).call(self)
}

function convertError (error, useRawErrorObjects) {
  if (error) {
    if (!(error instanceof ChatServiceError)) {
      debuglog(error)
    }
    if (!useRawErrorObjects) {
      return error.toString()
    }
  }
  return error
}

module.exports = {
  asyncLimit,
  checkNameSymbols,
  execHook,
  possiblyCallback,
  convertError,
  run
}
