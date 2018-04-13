config         = require "config"
async          = require "async"
retry          = require "retry"
_              = require "underscore"
io             = require "socket.io-client"
debug          = (require "debug") "app:app-updater"
{ host, port } = config.osUpdater.endpoint
{ mqttTopic }  = config.osUpdater
osUpdaterUrl   = "http://#{host}:#{port}"

log = (require "../lib/Logger") "OS Updater"

socket         = null

module.exports = (mqttSocket, state) ->

	_onConnectedToOsUpdater = ->
		log.info "Connected to os updater #{osUpdaterUrl}"

	_onSioError = (error) ->
		log.error "Error on socket.io #{error.message}"

	_onDisconnect = ->
		log.info "Disconnected from os updater"

	_handleVersion = (version) ->
		log.info "Received request to update OS to version #{version}"
		socket.emit "update-dm", version, (error) -> log.error error if error

	_onErrorLog = (error) ->
		state.publishLog "error", "OS updater: #{error}"

	_onLogs = (updateLog) ->
		updateLog = JSON.stringify(updateLog) if typeof updateLog is "object"
		log.info "Updating log: #{updateLog}"
		state.setWork "State: #{updateLog}"

	return {
		init: ->
			log.info "Initializing"

			socket or= io osUpdaterUrl

			socket
				.on "connect",    _onConnectedToOsUpdater
				.on "logs",       _onLogs
				.on "errorLog",   _onErrorLog
				.on "error",      _onSioError
				.on "disconnect", _onDisconnect

			mqttSocket.on mqttTopic, _handleVersion
			mqttSocket.customSubscribe
				topic: mqttTopic
				opts:
					qos: 2

			, (error) ->
				log.error "An error occured subscribing to the topic #{mqttTopic}: #{error.message}" if error


		clean: ->
			log.info "Cleaning"
			mqttSocket.removeListener mqttTopic, _handleVersion

			socket.off "connect"
			socket.off "logs"
			socket.off "errorLog"
			socket.off "error"
			socket.off "disconnect"

	}
