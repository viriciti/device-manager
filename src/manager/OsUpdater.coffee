config = require "config"
async  = require "async"
retry  = require "retry"
_      = require "underscore"
debug  = (require "debug") "app:app-updater"

log = (require "../lib/Logger") "OS Updater"

{ updateDevicesOs } = (require "../actions/osActions")()

module.exports = (mqttSocket) ->
	operations = []
	# leVersion = null
	# doingStuff = false

	# _handleVersion = (version) ->
	#     leVersion = version
	#     startRetry() unless doingStuff

	# startRetry = () ->
	#     doingStuff = true
	#     { retryInterval, retryTimes } = config.osUpdater.endpoint

	#     async.retry { interval: retryInterval, times: retryTimes }, (next) ->
	#         updateDevicesOs leVersion, (error) ->
	#             return next error if error.message is "ECONNREFUSED"
	#             log.error error.message if error
	#             next()

	#     , (error) ->
	#         doingStuff = false
	#         return log.error error.message if error
	#         log.info "Device updated to version #{version}"

	_handleVersion = (version) ->  
		if not _.isEmpty operations
			log.info "New request arrived with version #{version}. Canceling old requests!"
			_.forEach operations, (o) -> o.stop()

		log.info "Updating device to version `#{version}`"

		operation = retry.operation
			retries: 30,
			factor: 3,
			minTimeout: 1 * 1000
			randomize: false

		operations.push operation

		operation.attempt (currentAttempt) ->
			updateDevicesOs version, (error, result) ->
				return operation.retry error if error?.message is "ECONNREFUSED"
				if error
					log.error "Error: #{error}" 
				else
					log.info "Success: #{result}"

				_.forEach operations, (o) -> o.stop()
				operations = []
				



	return {
		init: ->
			{ mqttTopic } = config.osUpdater

			mqttSocket.on "enabledOsVersion", _handleVersion

			mqttSocket.customSubscribe
				topic: mqttTopic
				opts:
					qos: 2

			, (error) ->
				log.error "An error occured subscribing to the topic #{mqttTopic}: #{error.message}" if error


		clean: ->
			mqttSocket.removeListener "enabledOsVersion", _handleVersion
	}