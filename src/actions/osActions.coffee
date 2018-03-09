request = require "request"
config  = require "config"
async   = require "async"
debug   = (require "debug") "app:actions:os"

{ host, port, path } = config.osUpdater.endpoint

module.exports = ->
	
	updateDevicesOs = (version, cb) ->
		request.post "http://#{host}:#{port}#{path}"
			, json: { version }
			, (error, response, body) ->
				return cb new Error 'ECONNREFUSED' if error?.code is 'ECONNREFUSED'
					
				if response?.statusCode isnt 200
					return cb new Error body

				cb null, body
				
	return { updateDevicesOs }
