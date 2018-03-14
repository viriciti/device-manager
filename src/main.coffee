async      = require "async"
config     = require "config"
debug      = (require "debug") "app:main"
devicemqtt = require "@tn-group/device-mqtt"
os         = require "os"
schedule   = require "node-schedule"

log        = (require "./lib/Logger") "Main"
AppUpdater = require './manager/AppUpdater'
OsUpdater  = require './manager/OsUpdater'

HOSTNAME = os.hostname()

# Will message
will =
	topic   : "devices/#{HOSTNAME}/status"
	payload : "offline"


# Queue init
queue = async.queue (task, cb) ->
	log.info "Executing action: `#{task.name}`"
	task.fn cb

log.warn "Booting up manager..."

# Init Docker
Docker = require "./lib/Docker"
docker = new Docker config.docker
docker.init()

# Init devicemqtt
{ host, port, tls, connectionOptions, tlsActive } = config.mqtt

tls = null unless tlsActive

client = devicemqtt {
	host
	port
	tls
	clientId: HOSTNAME
	extraOpts: connectionOptions
}

state       = null
updater     = null
checkingJob = null

client.on "connected", (socket) ->
	state.clean()   if state
	updater.clean() if updater
	osUpdater.clean() if osUpdater

	log.info "Connected to the MQTT Broker"

	# Init stateManager
	state = (require "./manager/StateManager") socket, docker, HOSTNAME
	state.init()

	debug "Kicking state"
	state.kickState()
	state.notifyOnlineStatus (error) ->
		throw error if error
		log.info "Initial state sent successfully!"

	# Init app updater
	updater = AppUpdater docker, state, socket
	updater.init()

	# Init os updater
	osUpdater = OsUpdater socket
	osUpdater.init()

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

	# Init actionMap
	{ execute } = (require "./manager/actionsMap") docker, state, updater

	_onAction = (action, payload, reply) ->
		log.info "New action received: \n #{action} -
			Payload: #{JSON.stringify payload}"

		actionFn =
			name: action
			fn: (cb) ->
				debug "Action `#{action}` being executed"
				execute { action, payload }, (error, result) ->
					debug "Received an error: #{error.message}" if error
					debug "Received result for action: #{action} - #{result}"

					if error
						return reply.send type: "error", data: error.message, (mqttErr, ack) ->
							if mqttErr
								log.error "An error occured sending the message: #{error.message}"
								return cb()

					reply.send type: "success", data: result, (error, ack) ->
						log.error "An error occured sending the message: #{error.message}" if error
						if action isnt "getContainerLogs"
							debug "Action `#{action}` kicking state"
							state.kickState()

						cb()



		queue.push actionFn, (error) ->
			if error
				log.error "Error processing action `#{action}`: #{error.message}"
			else
				log.info "Action `#{action}` completed"
			debug "Action queue lenght: #{queue.length()}"

		debug "Action queue lenght: #{queue.length()}"

	socket
		.on "action", _onAction
		.once "disconnected", ->
			checkingJob.cancel()
			log.warn "Disconnected from MQTT Broker"
			socket.removeListener "action", _onAction

client.on "error", (error) ->
	log.error "An error occured: #{error.message}"

client.connect will
