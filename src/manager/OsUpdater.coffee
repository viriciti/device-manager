config        = require "config"
async         = require "async"
retry         = require "retry"
_             = require "underscore"
io            = require "socket.io-client"
debug         = (require "debug") "app:app-updater"
{ mqttTopic } = config.osUpdater


log = (require "../lib/Logger") "OS Updater"

module.exports = (mqttSocket, state) ->
	{ host, port } = config.osUpdater.endpoint

	osUpdaterUrl = "http://#{host}:#{port}"

	return {
		init: ->
			_handleVersion = (version) ->
				log.info "Received request to update OS to version #{version}"

				socket.emit "update", version, (error) -> log.error error if error

			_onErrorLog = (error) ->
				log.error "os-updater error! #{error}"
				state.setWork "OS updater ERROR!"

			_onLogs = (updateLog) ->
				updateLog = JSON.stringify(updateLog) if typeof updateLog is "object"

				log.info "Updating log: #{updateLog}"

				state.setWork "State: #{updateLog}"

			socket = io osUpdaterUrl
			socket
				.on "connect", -> log.info "Connected to os updater #{osUpdaterUrl}"
				.on "logs", _onLogs
				.on "errorLog", _onErrorLog
				.on "error", (error) -> log.error "Error on socket.io #{error.message}"
				.on "disconnect", -> log.info "Disconnected from os updater"

			mqttSocket.on mqttTopic, _handleVersion
			mqttSocket.customSubscribe
				topic: mqttTopic
				opts:
					qos: 2

			, (error) ->
				log.error "An error occured subscribing to the topic #{mqttTopic}: #{error.message}" if error


		clean: ->
			mqttSocket.removeListener mqttTopic, _handleVersion
	}
