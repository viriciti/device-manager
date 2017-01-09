request = require "request"
config  = require "config"
debug   = (require "debug") "app:actions:os"
log     = (require "../lib/Logger") "os actions"

{ host, port, path } = config.osUpdater.endpoint

module.exports = ->
	updateDevicesOs = (version, cb) ->
		log.info "Updating device to version `#{version}`"

		request.post "http://#{host}:#{port}#{path}"
		, json: { version }
		, (error, response, body) ->
			return cb error if error

			if response.statusCode isnt 200
				return cb new Error "Status code is #{response.statusCode}. Check ivh2-os-updater for more logs!"

			cb()

	return { updateDevicesOs }
