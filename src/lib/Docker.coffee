_                = require "underscore"
{ EventEmitter } = require "events"
async            = require "async"
debug            = (require "debug") "app:docker"
Dockerode        = require "dockerode"
jsonstream2      = require "jsonstream2"
moment           = require "moment"
pump             = require "pump"
rimraf           = require "rimraf"
S                = require "string"

log              = (require "./Logger") "Docker"
DockerLogsParser = require "./DockerLogsParser"
LayerFixer       = require "./LayerFixer"

class Docker extends EventEmitter
	constructor: ({ @socketPath, @maxRetries, @registry_auth }) ->
		@dockerClient = @_createConnection()
		@logsParser = new DockerLogsParser @

	_createConnection: ->
		return new Dockerode socketPath: @socketPath, maxRetries: @maxRetries

	init: ->
		@_emitData()

	_emitData: =>
		_handleStreamError = (error) =>
			@emit "error", error

		_handleStreamData = (event) =>
			try
				event = JSON.parse event
			catch error
				log.error "Error parsing event data:\n#{event.toString()}"
				return @emit "error", error

			if (event.status)
				@_handleStatusContainers event

			@emit "logs", @logsParser.parseLogs event

		@dockerClient.getEvents (error, stream) =>
			@emit "error", error if error

			stream
				.on "error", _handleStreamError
				.on "data", _handleStreamData
				.on "close", ->
					log.warn "Closed connection to Docker daemon."

	_handleStatusContainers: (logs) ->
		@emit "statusContainers"

	stop: ->
		@dockerClient = null




	getDockerInfo: (cb) =>
		@dockerClient.version (error, info) ->
			return cb error if error
			cb null, {
				version: info.Version,
				linuxKernel: info.KernelVersion
			}




	###
		Images API
	###
	pullImage: ({ name }, cb) =>
		next = _.once cb

		log.info "Pull image `#{name}`..."

		credentials    = null
		credentials    = @registry_auth.credentials if @registry_auth.required

		@dockerClient.pull name, { authconfig: credentials }, (error, stream) =>
			if error
				log.error "Error pulling `#{name}`: #{error.message}"
				return next error

			pulling = false

			_pullingPingTimeout = setInterval =>
				return if not pulling
				debug "Emitting pull logs"
				@emit "logs",
					message: "Pulling"
					image: name
					type: "action"
					time: moment().format('MMMM Do YYYY, h:mm:ss a')
			, 3000

			pump [
				stream
				jsonstream2.parse()
				new LayerFixer()
			], (error) ->
				pulling = false
				clearInterval _pullingPingTimeout

				log.error "An error occured in pull: #{error.message}" if error

				if error?.conflictingDirectory
					return rimraf error.conflictingDirectory, (error) =>
						if error
							log.error error.message
							return next error
						@pullImage { name }, next

				next error

	listImages: (cb) =>
		@dockerClient.listImages (error, images) =>
			if error
				log.error "Error listing images: #{error.message}"
				return cb error

			images = _.filter images, (image) ->
				(image.RepoTags isnt null) and (image.RepoTags[0] isnt "<none>:<none>")

			async.map images, (image, next) =>
				# In order to inspect the image, one tag is needed. RepoTags[0] is enough.
				@getImageByName image.RepoTags[0], (error, imageInfo) ->
					return next error if error
					next null, imageInfo
			, cb

	getImageByName: (name, cb) ->
		image = @dockerClient.getImage name
		image.inspect (error, info) ->
			return cb error if error
			cb null, {
				id: info.Id,
				name: name,
				tags: info.RepoTags,
				size: info.Size,
				virtualSize: info.VirtualSize
			}

	removeImage: ({ id, force }, cb) ->
		log.info "Removing image, force", force
		image = @dockerClient.getImage id
		image.remove { force }, (error) ->
			if error
				log.error "Error removing image: #{error.message}"
				return cb error

			cb null, "Image #{id} removed correctly"


	###
		Containers API
	###
	listContainers: (cb) =>
		@dockerClient.listContainers all:true, (error, containers) =>
			return cb error if error
			async.map containers, (container, next) =>
				###
					container.Names is an array of names in the format "/name".
					Then, only the first one is needed without the slash.
				###
				@getContainerByName container.Names[0].replace("/",""), (err, container) ->
					return next() if not container
					return next error if error
					next null, container
			, (error, formattedContainers) ->
				return cb error if error
				# Compact because sometimes the array contains undefined values
				cb null, _.compact formattedContainers


	listContainersNames: (cb) =>
		@dockerClient.listContainers all:true, (error, containers) =>
			return cb error if error
			async.map containers, (container, next) =>
				next null, container.Names[0].replace "/", ""
			, (error, containers) ->
				cb error, _(containers).compact()

	getContainerByName: (name, cb) =>
		container = @dockerClient.getContainer name
		container.inspect { size: 1 }, (error, info) =>
			return cb error if error
			###
				Here a new object is created because
				not all the information of the container are useful
			###
			cb null, @_createContainerObject info

	_createContainerObject: (containerInfo) ->
		started = moment(new Date(containerInfo.State.StartedAt)).fromNow()

		if not containerInfo.State.Running
			stopped = moment(new Date(containerInfo.State.FinishedAt)).fromNow()
		else
			stopped = ""

		{
			Id            : containerInfo.Id
			name          : containerInfo.Name.replace("/",""),
			commands      : containerInfo.Config.Cmd,
			restartPolicy :
				type: containerInfo.HostConfig.RestartPolicy.Name
				maxRetriesCount: containerInfo.HostConfig.RestartPolicy.MaximumRetryCount
			privileged    : containerInfo.HostConfig.Privileged
			readOnly      : containerInfo.HostConfig.ReadonlyRootfs
			image         : containerInfo.Config.Image
			networkMode   : containerInfo.HostConfig.NetworkMode
			state         :
				status: containerInfo.State.Status
				running: containerInfo.State.Running
				started: started
				stopped: stopped
			ports         : containerInfo.HostConfig.PortBindings
			environment   : containerInfo.Config.Env
			sizeFilesystem: containerInfo.SizeRw #this information is in byte
			sizeRootFilesystem : containerInfo.SizeRootFs #this information is in byte
			mounts        : containerInfo.Mounts.filter (mount) ->
				hostPath: mount.Source, containerPath: mount.Destination, mode: mount.Mode
			labels: containerInfo.Config.Labels

		}


	createContainer: ({ containerProps }, cb) ->
		log.info "Creating container", containerProps.name
		@dockerClient.createContainer containerProps, (error, created) ->
			if error
				log.error "Creating container `#{containerProps.name}` failed: #{error.message}"
				return cb error

			cb null, created

	startContainer: ({ id }, cb) ->
		log.info "Starting container `#{id}`"
		container = @dockerClient.getContainer id
		container.start (error) ->
			if error
				log.error "Starting container `#{id}` failed: #{error.message}"
				return cb error

			cb null, "Container #{id} started correctly"

	restartContainer: ({ id }, cb) ->
		log.info "Restarting container `#{id}`"
		container = @dockerClient.getContainer id
		container.restart (error) ->
			if error
				log.error "Restarting container `#{id}` failed: #{error.message}"
				return cb error

			cb null, "Container #{id} restarted correctly"

	removeContainer: ({ id, force = false }, cb) ->
		log.info "Removing container `#{id}`"

		@listContainers (error, containers) =>
			if error
				log.error "Error listing containers: #{error.message}"
				return cb error

			toRemove = _.filter containers, (c) -> (S c.name).contains id

			async.eachSeries toRemove, (c, cb) =>
				(@dockerClient.getContainer c.Id).remove { force }, (error) ->
					if error
						log.error "Error removing `#{id}`: #{error.message}"
					cb error
			, (error) ->
				if error
					log.error "Error in removing one of the containers"
				else
					log.info "Removed all containers"

				cb error

	getContainerLogs: ({ id, numOfLogs }, cb) ->
		buffer = []

		log.info "Getting `#{numOfLogs}` logs for `#{id}`"

		container = @dockerClient.getContainer id
		logsOpts =
			stdout: 1
			stderr: 1
			tail: numOfLogs
			follow: 0

		optsf =
			path: "/containers/#{id}/logs?"
			method: "GET"
			isStream: false
			statusCodes:
				200: true,
				404: "no such container"
				500: "server error"
			options: logsOpts


		# container.modem.dial optsf, (error, data) ->
		# 	cb error, data.toString()

		container.logs logsOpts, (error, stream) =>
			if error
				log.error "Error retrieving container logs for `#{id}`"
				return cb error

			stream
				.on "data", (data) =>
					buffer.push data.toString()
				.once "end", ->
					log.info "log stream for `#{id}` ended."
					cb null, buffer

module.exports = Docker
