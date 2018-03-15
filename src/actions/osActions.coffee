request = require "request"
config  = require "config"
async   = require "async"
debug   = (require "debug") "app:actions:os"

{ host, port, path } = config.osUpdater.endpoint

module.exports = (state) ->

	updateDevicesOs = (version, cb) ->
		state.setWork "Updating OS to version #{version}"

		request.post "http://#{host}:#{port}#{path}"
			, json: { version }
			, (error, response, body) ->
				state.setWork "Idle"		
				
				return cb new Error 'ECONNREFUSED' if error?.code is 'ECONNREFUSED'
				return cb new Error body if response?.statusCode isnt 200
					
				cb null, body
				
	return { updateDevicesOs }
