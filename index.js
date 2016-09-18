'use strict'

var semver = require('semver')

// Choosing between a source ES6 syntax and a babel transpiled
// ES5. Note that ES6 source code uses functions that are available in
// node >= 0.12 environment, so no globals modifications are required.
if (semver.lt(process.version, '6.0.0')) {
  module.exports = require('./lib/ChatService')
} else {
  module.exports = require('./src/ChatService')
}
