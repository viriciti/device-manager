async      = require "async"
config     = require "config"
debug      = (require "debug") "app:main"
devicemqtt = require "@tn-group/device-mqtt"
os         = require "os"
schedule   = require "node-schedule"

log          = require("./lib/Logger") "Main"
Docker       = require "./lib/Docker"
AppUpdater   = require './manager/AppUpdater'
OsUpdater    = require './manager/OsUpdater'
StateManager = require './manager/StateManager'

HOSTNAME     = os.hostname()

mqttSocket   = null

lastWill =
	topic   : "devices/#{HOSTNAME}/status"
	payload : "offline"

queue = async.queue (task, cb) ->
	log.info "Executing action: `#{task.name}`"
	task.fn cb

log.info "Booting up manager..."

docker = new Docker config.docker
docker.init()

state     = StateManager mqttSocket, docker, HOSTNAME
updater   = AppUpdater   docker, state
osUpdater = OsUpdater    state

docker.on "logs", state.publishLog

{ execute } = require("./manager/actionsMap") docker, state, updater

{ host, port, tls, connectionOptions, tlsActive } = config.mqtt

tls = null if config.development
client = devicemqtt {
	host
	port
	tls
	clientId:  HOSTNAME
	extraOpts: connectionOptions
}

checkingJob = null # TODO quit @ disconnect

# Ping for keeping the connection on
pingJob  = schedule.scheduleJob "0 */#{config.cronJobs.ping} * * * *",  state.ping
stateJob = schedule.scheduleJob "0 */#{config.cronJobs.state} * * * *", state.throttledSendState

# Period checking of the Docker state
checkingJob = schedule.scheduleJob "0 */#{config.cronJobs.checkDockerStatus} * * * *", ->
	if updater.isUpdating()
		log.info "Not checking Docker: already updating."
		return

	log.info "Checking Docker state..."
	updater.update state.getGlobalGroups(), state.getGroups(), (error, result) ->
		if error
			return log.error "Error in updater update: #{error.message}"

		log.info "Finished checking Docker state..."

client.on "connected", (socket) ->
	mqttSocket = socket

	handleSocketError = (error) ->
		return log.error error.message if error

	log.info "Connected to the MQTT Broker"

	debug "Kicking state"
	state.throttledSendState()
	state.notifyOnlineStatus (error) ->
		throw error if error
		log.info "Initial state sent successfully!"

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

						if action isnt "getContainerLogs"
							debug "Action `#{action}` kicking state"
							state.throttledSendState()

						cb()

		queue.push task, (error) ->
			debug "Action queue length: #{queue.length()}"
			return log.error "Error processing action `#{action}`: #{error.message}" if error
			log.info "Action `#{action}` completed"

	socket
		.on "action", _onAction
		.on "error",  handleSocketError

	socket.once "disconnected", ->
		log.warn "Disconnected from mqtt"

		socket.removeListener "action", _onAction
		socket.removeListener "error", handleSocketError

		pingJob.cancel() # TODO activate ping job and cancel this one indeed
		stateJob.cancel()

client.on "error", (error) ->
	log.error "An error occured: #{error.message}"

client.connect lastWill
