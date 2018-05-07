config         = require "config"
async          = require "async"
retry          = require "retry"
_              = require "underscore"
debug          = require("debug")         "app:os-updater"
log            = require("../lib/Logger") "OS Updater"

module.exports = (sioSocket, state) ->
	_onConnectedToOsUpdater = ->
		log.info "Connected to os updater"

	_onSioError = (error) ->
		log.error "Error on socket.io #{error.message}"

	_onDisconnect = ->
		log.info "Disconnected from os updater"

	handleVersion = (version) ->
		log.info "Received request to update OS to version: '#{version}'"
		sioSocket.emit "update-dm", version, (error) ->
			if error
				log.error error
				state.setWork "State: #{error}"
				state.publishLog "error", "OS updater: #{error}"

	_onErrorLog = (error) ->
		log.error "#{error}"
		state.publishLog "error", "OS updater: #{error}"

	_onLogs = (updateLog) ->
		updateLog = JSON.stringify(updateLog) if typeof updateLog is "object"
		log.info "#{updateLog}"
		state.setWork "State: #{updateLog}"
		state.publishLog "info", "OS updater: #{updateLog}"
		# TODO send to state.publishlog

	sioSocket
		.on "connect",    _onConnectedToOsUpdater
		.on "logs",       _onLogs
		.on "errorLog",   _onErrorLog
		.on "error",      _onSioError
		.on "disconnect", _onDisconnect


	return { handleVersion }
