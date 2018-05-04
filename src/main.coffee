_          = require "underscore"
async      = require "async"
config     = require "config"
debug      = (require "debug") "app:main"
devicemqtt = require "device-mqtt"
os         = require "os"
io         = require "socket.io-client"
schedule   = require "node-schedule"

log          = require("./lib/Logger") "Main"
Docker       = require "./lib/Docker"
AppUpdater   = require './manager/AppUpdater'
OsUpdater    = require './manager/OsUpdater'
StateManager = require './manager/StateManager'

osUpdaterUrl   = "http://#{config.osUpdater.host}:#{config.osUpdater.port}"

mqttSocket    = null
getMqttSocket = -> mqttSocket
sioSocket     = io osUpdaterUrl

lastWill =
	topic   : "devices/#{config.host}/status"
	payload : "offline"

queue = async.queue (task, cb) ->
	log.info "Executing action: `#{task.name}`"
	task.fn cb

log.info "Booting up manager..."

docker     = new Docker   config.docker
state      = StateManager getMqttSocket, docker, config.host
appUpdater = AppUpdater   docker,        state
osUpdater  = OsUpdater    sioSocket,     state

docker.on "logs", ({ type, message, time } = {}) ->
	state.publishLog type, message, time

{ execute } = require("./manager/actionsMap") docker, state, appUpdater

client = devicemqtt _.extend {}, config.mqtt, (if config.development then tls: null else {})

cronJob = schedule.scheduleJob "0 */#{config.cronJob} * * * *", ->
	debug "Running cron job"
	if appUpdater.isUpdating()
		log.info "Not checking Docker: already updating."
		return

	state.throttledSendState()

	log.info "Checking Docker state..."
	appUpdater.update state.getGlobalGroups(), state.getGroups(), (error, result) ->
		return log.error "Error in appUpdater update: #{error.message}" if error
		log.info "Finished checking Docker state..."

client.on "connected", (socket) ->
	log.info "Connected to the MQTT Broker socket id: #{socket.id}"

	mqttSocket = socket

	state.notifyOnlineStatus()
	state.throttledSendState()

	_onAction = (action, payload, reply) ->
		log.info "New action received: \n #{action} - Payload: #{JSON.stringify payload}"
		debug "Action queue length: #{queue.length()}"

		task =
			name: action
			fn: (cb) ->
				debug "Action queue length: #{queue.length()}"
				debug "Action `#{action}` being executed"
				execute { action, payload }, (error, result) ->
					debug "Received an error: #{error.message}" if error
					debug "Received result for action: #{action} - #{result}"

					if error
						return reply.send type: "error", data: error.message, (mqttErr, ack) ->
							log.error "An error occured sending the message: #{error.message}" if mqttErr
							return cb()

					reply.send type: "success", data: result, (error, ack) ->
						log.error "An error occured sending the message: #{error.message}" if error

						return cb() if action is "getContainerLogs"

						debug "Action `#{action}` kicking state"
						state.throttledSendState()

						cb()

		queue.push task, (error) ->
			debug "Action queue length: #{queue.length()}"
			return log.error "Error processing action `#{action}`: #{error.message}" if error
			log.info "Action `#{action}` completed"

	socket.customSubscribe
		topic: config.osUpdater.topic
		opts:
			qos: 1
	, (error, granted) ->
		return log.error "An error occured subscribing to the topic
			#{config.osUpdater.topic}: #{error.message}" if error
		debug "Successful subscribe", granted

	_onSocketError = (error) ->
		log.error "MQTT socket error!: #{error.message}" if error

	socket
		.on   "action",               _onAction
		.on   "error",                _onSocketError
		.on   "global:collection",    appUpdater.debouncedHandleCollection
		.on   config.osUpdater.topic, osUpdater.handleVersion
		.once "disconnected", ->
			log.warn "Disconnected from mqtt"
			socket.removeListener "action",               _onAction
			socket.removeListener "error",                _onSocketError
			socket.removeListener "global:collection",    appUpdater.debouncedHandleCollection
			socket.removeListener config.osUpdater.topic, osUpdater.handleVersion

debug "Connecting to mqtt at #{config.mqtt.host}:#{config.mqtt.port}"
client
	.on "error", (error) ->
		log.error "MWTT client error occured: #{error.message}"
	.on "reconnecting", (error) ->
		log.info "Reconectiiing"
	.connect lastWill

module.exports = {
	client
	queue
	mqttSocket
	state
}
