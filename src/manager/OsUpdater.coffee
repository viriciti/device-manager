config = require "config"
async  = require "async"
retry  = require "retry"
_      = require "underscore"
debug  = (require "debug") "app:app-updater"

log = (require "../lib/Logger") "OS Updater"


module.exports = (mqttSocket, state) ->
	{ updateDevicesOs } = (require "../actions/osActions") state

	operations = []

	_handleVersion = (version) ->  
		if not _.isEmpty operations
			log.info "New request arrived with version #{version}. Canceling old requests!"
			_.forEach operations, (o) -> o.stop()
			operations = []

		log.info "Updating device to version `#{version}`"

		operation = retry.operation
			retries: 30,
			factor: 3,
			minTimeout: 1 * 1000

		operations.push operation

		operation.attempt (currentAttempt) ->
			console.log operations.length
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

			mqttSocket.on mqttTopic, _handleVersion

			mqttSocket.customSubscribe
				topic: mqttTopic
				opts:
					qos: 2

			, (error) ->
				log.error "An error occured subscribing to the topic #{mqttTopic}: #{error.message}" if error


		clean: ->
			{ mqttTopic } = config.osUpdater

			mqttSocket.removeListener mqttTopic, _handleVersion
	}