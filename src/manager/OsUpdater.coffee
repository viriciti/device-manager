config = require "config"
async  = require "async"
retry  = require "retry"
_      = require "underscore"
io     = require "socket.io-client"
debug  = (require "debug") "app:app-updater"

log = (require "../lib/Logger") "OS Updater"


module.exports = (mqttSocket, state) ->
	{ updateDevicesOs } = (require "../actions/osActions") state
	{ host, port, event } = config.osUpdater.endpoint

	osUpdaterUrl = "http://#{host}:#{port}"
	socket = null

	_handleVersion = (version) ->
		log.info "Received request to update OS to version #{version}"

		_onLogs = (updateLog) ->
			log.info "Updating log: #{updateLog}"

			if updateLog is "done"
				state.setWork "Idle"
				log.info "OS updated correctly to version #{version}"

			state.setWork "Updating OS: #{updateLog}"

		socket
			.on "logs", _onLogs
			.on "disconnect", -> socket.removeListener "logs", _onLogs

		socket.emit "update", version, (error) ->
			return log.error error if error

	return {
		init: ->
			{ mqttTopic } = config.osUpdater

			socket = io osUpdaterUrl
			socket
				.on "connect", -> log.info "Connected to os updater #{osUpdaterUrl}"
				.on "error", (error) -> log.error error.message if error

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