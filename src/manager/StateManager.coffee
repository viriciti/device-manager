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

DATE_FORMAT = "YYYY-MM-DD hh:mm:ss"

module.exports = (getSocket, docker, deviceId) ->

	checkSerialNumber = ->
		return true if config.development
		certFile = fs.readFileSync config.mqtt.tls.cert
		certSerial = (S certFile.toString())
			.between "CN=vc-", "/name"
			.s

		debug "Check serial number positive:", deviceId is "vc-#{certSerial}"
		deviceId is "vc-#{certSerial}"

	localState =
		work: "idle"
		errors: []
		globalGroups: {}
		isSerialCorrect: checkSerialNumber()

	groupsFilePath = config.groups.path

	customPublish = (opts, cb) ->
		socket = getSocket()
		return cb?() unless socket
		socket.customPublish opts, cb

	ping = (cb) ->
		customPublish
			topic: "ping"
			message: deviceId
		, (error) ->
			log.error error if error

	_sendStateToMqtt = (cb) ->
		log.info "Sending state.."
		_generateStateObject (error, state) ->
			if error
				log.error "Not sending state: #{error.message}"
				return cb? error

			debug "State is", JSON.stringify _.omit state, ["images", "containers"]

			stateStr = JSON.stringify state
			byteLength = Buffer.byteLength( stateStr, 'utf8' )
			log.warn "Buffer.byteLength: #{byteLength}" if byteLength > 20000 # .02MB spam per 2 sec = 864MB in 24 hrs

			customPublish
				topic: "devices/#{deviceId}/state"
				message: stateStr
				opts:
					retain: true
					qos: 2
			, (error) ->
				if error
					log.error "Error in custom state publish: #{error.message}"
				else
					log.info "State published!"

				cb? error

	throttledSendState = _.throttle (-> _sendStateToMqtt()), 2000

	notifyOnlineStatus = (cb) ->
		log.info "Setting status: online"
		customPublish
			topic: "devices/#{deviceId}/status"
			message: "online"
			opts:
				retain: true
				qos: 2
		, (error) ->
			if error
				log.error "Error in online status publish: #{error.message}"

			cb error

	setWork = (work) ->
		debug "Set work", work
		localState = Object.assign {}, localState, { work }
		throttledSendState()

	publishLog = (type, message, time) ->
		message = message.message if typeof message is "object"
		data    = { type: type or "info", message, time: time or Date.now() / 1000 }
		data    = JSON.stringify data
		debug "Sending: #{data}"
		customPublish {
			topic: "devices/#{deviceId}/logs"
			message: data
			opts:
				retain: true
				qos: 2
		}

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
		throttledSendState()

	setGlobalGroups = (globalGroups) ->
		debug "Set global groups to: #{JSON.stringify globalGroups}"
		localState = _.extend {}, localState, { globalGroups }

	getGlobalGroups = ->
		localState.globalGroups

	_getOSVersion = (cb) ->
		fs.readFile "/version", (error, version) ->
			return cb new Error "Error reading version file: #{error.message}" if error
			return cb new Error "Version is undefined" unless version

			cb null, version.toString().trim()

	_generateStateObject = (cb) ->
		debug "Generating state object"

		async.parallel
			images:     docker.listImages
			containers: docker.listContainers
			systemInfo: docker.getDockerInfo
			osVersion:  _getOSVersion

		, (error, { images, containers, systemInfo, osVersion }) ->
			if error
				log.error "Error generating state object: #{error.message}"
				return cb error

			state = {}
			systemInfo = _.extend systemInfo, getIpAddresses()

			unless config.development
				systemInfo = _.extend systemInfo, { osVersion }, { dmVersion: (require path.resolve __dirname, "../package.json").version }

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
		getDeviceId
		getGlobalGroups
		getGroups
		notifyOnlineStatus
		ping
		publishLog
		setGlobalGroups
		setGroups
		setWork
		throttledSendState
	}

