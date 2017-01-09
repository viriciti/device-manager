_        = require "underscore"
async    = require "async"
config   = require "config"
debug    = (require "debug") "app:state-manager"
fs       = require "fs"
path     = require "path"
moment   = require "moment"
os       = require "os"
S        = require "string"
schedule = require "node-schedule"

getIpAddresses = require "../helpers/get_ipaddresses"
log            = (require "../lib/Logger") "StateManager"

module.exports = (socket, docker, deviceId) ->
	localState =
		work: ""
		globalGroups: {}
		isSerialCorrect: ""

	groupsFilePath = config.groups.path
	pingJob = null
	stateJob = null


	init = ->
		log.info "Initializing."
		localState.work = "idle"
		# localState.isSerialCorrect = checkSerialNumber()

		socket.on "error", _handleSocketError

		docker.on "logs", _handleDockerLogs

		docker.on "statusContainers", _handleStatusContainers

		# Ping for keeping the connection on
		pingJob = schedule.scheduleJob "0 */#{config.cronJobs.ping} * * * *", ->
			debug "Scheduled ping: #{config.cronJobs.ping}"
			socket.customPublish
				topic: "ping"
				message: deviceId
			, (error) ->
				log.error error if error

		stateJob = schedule.scheduleJob "0 */#{config.cronJobs.state} * * * *", ->
			debug "Scheduled kick state: #{config.cronJobs.state}"
			kickState()

	clean = ->
		log.info "Cleaning."
		socket.removeListener "error", _handleSocketError
		docker.removeListener "statusContainers", _handleStatusContainers
		docker.removeListener "logs", _handleDockerLogs
		pingJob.cancel()
		stateJob.cancel()

	_sendStateToMqtt = (cb) ->
		log.info "Sending state.."
		_generateStateObject (error, state) ->
			if error
				log.error "Not sending state: #{error.message}"
				return cb? error

			debug "State is", JSON.stringify _.omit state, ["images", "containers"]

			socket.customPublish
				topic: "devices/#{deviceId}/state"
				message: JSON.stringify state
				opts:
					retain: true
					qos: 2
			, (error) ->
				if error
					log.error "Error in cutom state publish: #{error.message}"
				else
					log.info "State published!"

				cb? error

	kickState = _.throttle (-> _sendStateToMqtt()), 2000

	notifyOnlineStatus = (cb) ->
		log.info "Setting status: online"
		socket.customPublish
			topic: "devices/#{deviceId}/status"
			message: "online"
			opts:
				retain: true
				qos: 2
		, (error) ->
			if error
				log.error "Error in online status publish: #{error.message}"

			cb error


	_handleDockerLogs = (logs) ->
		debug "Publishing log line.."
		socket.customPublish {
			topic: "devices/#{deviceId}/logs"
			message: JSON.stringify logs
		}

	_handleStatusContainers = (status) ->
		debug "Status containers is kicking state.."
		# kickState()


	setWork = (work) ->
		debug "Set work", work
		localState = Object.assign {}, localState, { work }

		debug "Set work kicking state"
		kickState()


	getDeviceId = -> deviceId


	getGroups = ->
		debug "Get groups"

		if not fs.existsSync groupsFilePath
			setGroups 1: "default"
			log.info "Groups file created correctly default configuration"

		try
			groups = JSON.parse (fs.readFileSync groupsFilePath).toString()
		catch error
			log.error "Error parsing groups file #{}: #{error.message}"
			setGroups 1: "default"

		groups = _.extend groups, 1: "default"

		debug "Get groups returning: #{JSON.stringify groups}"

		groups


	setGroups = (groups) ->
		groups = "#{JSON.stringify groups}\n"
		log.info "Setting groups file: #{groups}"
		fs.writeFileSync groupsFilePath, groups
		debug "Set groups kicking state..."
		kickState()

	setGlobalGroups = (globalGroups) ->
		debug "Set global groups to: #{JSON.stringify globalGroups}"
		localState = _(localState).extend {}, localState, { globalGroups }

	getGlobalGroups = ->
		localState.globalGroups


	checkSerialNumber = ->
		certFile = fs.readFileSync config.mqtt.tls.cert
		certSerial = (S certFile.toString())
			.between "CN=vc-", "/name"
			.s

		debug "Check serial number positive:", deviceId is "vc-#{certSerial}"
		deviceId is "vc-#{certSerial}"


	_handleSocketError = (error) ->
		return log.error error.message if error



	_getOSVersion = (cb) ->
		fs.readFile "/version", (error, version) ->
			if error
				log.error "Error in version file: #{error.version}"
				return cb error

			unless version
				errStr = "Version is undefined"
				log.error errStr
				return cb new Error errStr

			cb null, version.toString().trim()

	_generateStateObject = (cb) ->
		debug "Generating state object"

		async.parallel
			images: docker.listImages
			containers: docker.listContainers
			systemInfo: docker.getDockerInfo
			osVersion: _getOSVersion
			
		, (error, { images, containers, systemInfo, osVersion }) ->
			if error
				log.error "Error generating state object: #{error.message}"
				return cb error

			state = {}
			systemInfo = _.extend systemInfo, getIpAddresses()
			# systemInfo = _.extend systemInfo, { osVersion }, { dmVersion: (require path.resolve __dirname, "../package.json").version }
			groups = _(getGroups()).values()
			uptime = Math.floor(os.uptime() / 3600)

			state = _.extend {}, state,
				{ groups },
				{ systemInfo },
				{ images },
				{ containers },
				{ deviceId },
				{ uptime },
				{ serialIsCorrect: localState.isSerialCorrect },
				{ work: localState.work }

			cb null, state

	return {
		init
		kickState
		notifyOnlineStatus
		setWork
		clean
		getDeviceId
		getGroups
		setGroups
		setGlobalGroups
		getGlobalGroups
	}

