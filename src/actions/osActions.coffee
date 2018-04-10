_       = require "underscore"
request = require "request"
config  = require "config"
async   = require "async"
debug   = (require "debug") "app:actions:os"
io      = require "socket.io-client"
i2c     = require 'i2c-bus'

bus     = i2c.openSync 0

log = (require "../lib/Logger") "OS Updater"

module.exports = (state) ->

	reboot = (payload, cb) ->
		unless process.env.NODE_ENV is 'production'
			log.info "Reboot command received, not doing anything because env is #{process.env.NODE_ENV}"
			return

		log.info "Rebooting"

		# 0x55 is chip address
		# 0x62 is SOM soft reboot address
		# 0x57 is the required value
		bus.writeByteSync 0x55, 0x62, 0x57

	return { reboot }
