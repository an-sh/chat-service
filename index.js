'use strict'

var semver = require('semver')

// Choosing between a source ES6 syntax and a transpiled ES5.
if (semver.lt(process.version, '6.0.0')) {
  module.exports = require('./lib/ChatService')
} else {
  module.exports = require('./src/ChatService')
}
