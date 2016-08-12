'use strict'

var semver = require('semver')

// Choosing between a source ES6 syntax and a babel transpired
// ES5. Note that ES6 source code uses only functions that are
// available in ES5 environment (or lodash 4.x equivalents), so no
// globals modifications are required.
if (semver.lt(process.version, '6.0.0')) {
  module.exports = require('./lib/ChatService')
} else {
  module.exports = require('./src/ChatService')
}
