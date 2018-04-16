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

docker = new Docker config.docker
docker.init() # FIXME

state      = StateManager getMqttSocket, docker, config.host
appUpdater = AppUpdater   docker,        state
osUpdater  = OsUpdater    sioSocket,     state

docker.on "logs", ({ type, message, time } = {}) ->
	state.publishLog type, message, time

{ execute } = require("./manager/actionsMap") docker, state, appUpdater

client = devicemqtt _.extend {}, config.mqtt, (if config.development then tls: null else {})

checkingJob = null # TODO quit @ disconnect?

# Ping for keeping the connection on
pingJob     = schedule.scheduleJob "0 */#{config.cronJobs.ping} * * * *",  state.ping
stateJob    = schedule.scheduleJob "0 */#{config.cronJobs.state} * * * *", state.throttledSendState
checkingJob = schedule.scheduleJob "0 */#{config.cronJobs.checkDockerStatus} * * * *", ->
	if appUpdater.isUpdating()
		log.info "Not checking Docker: already updating."
		return

	log.info "Checking Docker state..."
	appUpdater.update state.getGlobalGroups(), state.getGroups(), (error, result) ->
		return log.error "Error in appUpdater update: #{error.message}" if error
		log.info "Finished checking Docker state..."

client.on "connected", (socket) ->
	log.info "Connected to the MQTT Broker"

	mqttSocket = socket

	handleSocketError = (error) ->
		return log.error "MQTT socket error!: #{error.message}" if error

	state.throttledSendState()

	state.notifyOnlineStatus (error) ->
		throw error if error

	_onAction = (action, payload, reply) ->
		log.info "New action received: \n #{action} - Payload: #{JSON.stringify payload}"
		debug "Action queue length: #{queue.length()}"

		task =
			name: action
			fn: (cb) ->
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

						# TODO Investigate, this looks funny, maybe there is a better way
						if action isnt "getContainerLogs"
							debug "Action `#{action}` kicking state"
							state.throttledSendState()

						cb()

		queue.push task, (error) ->
			debug "Action queue length: #{queue.length()}"
			return log.error "Error processing action `#{action}`: #{error.message}" if error
			log.info "Action `#{action}` completed"

	# NOTE Unsub?
	# I guess the entire scope of this socket is gone when we get a new socket after reconnect but still?
	# While testing publish to the osUpdater topic we just trigger once even after a couple of mqtt dis- reconnects.
	# So it looks like it's fine
	socket.customSubscribe
		topic: config.osUpdater.topic
		opts:
			qos: 2
	, (error) ->
		log.error "An error occured subscribing to the topic #{config.osUpdater.topic}: #{error.message}" if error

	socket
		.on "action",               _onAction
		.on "error",                handleSocketError
		.on config.osUpdater.topic, osUpdater.handleVersion

	socket.once "disconnected", ->
		log.warn "Disconnected from mqtt"

		socket.removeListener "action",               _onAction
		socket.removeListener "error",                handleSocketError
		socket.removeListener config.osUpdater.topic, osUpdater.handleVersion

client
	.on "error", (error) ->
		log.error "An error occured: #{error.message}"
	.connect lastWill

module.exports = {
	client
	queue
	mqttSocket
	state
}
