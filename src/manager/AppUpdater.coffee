_        = require "underscore"
async    = require "async"
config   = require "config"
debug    = (require "debug") "app:app-updater"
semver   = require "semver"

log = (require "../lib/Logger") "App Updater"

module.exports = (docker, state) ->
	updating = false

	isUpdating = -> updating

	_createGroupsMixin = (groups, deviceGroups) ->
		deviceGroupsLabels = _(deviceGroups).values()

		return _(deviceGroupsLabels).reduce (mixin, label) ->
			mixin = _(mixin).extend {}, mixin, groups[label]
			mixin
		, {}

	_getAppsToChange = (groupsMixin, deviceCurrentApps) ->
		manualAppsNames =_.chain deviceCurrentApps
			.pick (config, name) ->
				_(config.labels).isEmpty()
			.keys()
			.value()

		appsNotInTheMixin = _.chain deviceCurrentApps
			.omit _(manualAppsNames).union _(groupsMixin).keys()
			.keys()
			.value()

		appsToChange = _(groupsMixin).reduce (changes, config, name) ->
			if deviceCurrentApps[name]
				if (_isToUpdate config, deviceCurrentApps[name])
					changes.install = _(changes.install).union [config]
				else
					changes.skip = _(changes.skip).union [name]
			else
				changes.install = _(changes.install).union [config]

			changes
		, { install: [], remove: appsNotInTheMixin, skip: manualAppsNames }

		appsToChange

	_hasOutdatedApps = (appToInstall, currentApp) ->
		newVersion = _.last appToInstall.fromImage.split ":"
		currentVersion = _.last currentApp.image.split ":"

		return newVersion isnt currentVersion

	_hasDifferentMounts = (configMounts, currentMounts) ->
		_(configMounts).some (mount) ->
			return false if !(mount.split ":")[0]

			[ configSource, configDest ] = mount.split ":"
			hasMount = _.find currentMounts, ({ Source, Destination }) ->
				(Source is configSource) and (Destination is configDest)

			return false if hasMount
			return true

	_hasDifferentEnvironment = (configEnv, currentEnv) ->
		_(configEnv).some (env) ->
			not _(currentEnv).contains env

	_isToUpdate = (appToInstall, currentApp) ->
		(_hasDifferentEnvironment appToInstall.environment, currentApp.environment) ||
		(not _.isEqual appToInstall.privileged, currentApp.privileged) ||
		(not _.isEqual appToInstall.networkMode, currentApp.networkMode) ||
		(not _.isEqual appToInstall.restartPolicy, currentApp.restartPolicy?.type) ||
		(_hasDifferentMounts appToInstall.mounts, currentApp.mounts) ||
		(not _.isEqual appToInstall.fromImage, currentApp.image) ||
		(_hasOutdatedApps appToInstall, currentApp) ||
		(appToInstall.labels.group isnt currentApp.labels.group)


	_getCurrentApps = (cb) ->
		docker.listContainers (error, containers) ->
			return cb error if error
			cb null, containers.reduce (memo, container) ->
				memo[container.name] = container
				memo
			, {}

	_handleCollection = (label, collection) ->
		debug "Incoming collection", label

		# guard: only handle groups
		if label isnt "groups"
			return debug "Imcoming collection is not groups"

		# guard: collection may not be falsy
		if not collection
			return log.error "Incoming collection is undefined or null!"

		# guard: collection may not be empty
		if _.isEmpty collection
			return log.error "Incoming collection for groups is empty!"

		groups = collection
		state.setGlobalGroups groups

		deviceGroups = _(state.getGroups()).values()

		groups = _(groups).reduce (memo, apps, label) ->
			if _(deviceGroups).contains label
				memo[label] = apps

			memo
		, {}

		update groups, state.getGroups(), (error, result) ->
			return log.error error.message if error
			log.info "Device updated correctly!"

	debouncedHandleCollection = _.debounce _handleCollection, 2000

	update = (groups, deviceGroups, cb) ->
		debug "Updating..."
		debug "Global groups are #{JSON.stringify groups}"
		debug "Device groups are #{JSON.stringify deviceGroups}"

		return cb new Error "Global groups is empty! Not proceding." if _.isEmpty groups

		updating = true

		if ((_(groups).size() is 1) and not _(groups).has "default")
			return cb new Error "Size group is 1, but the group is not default"

		async.waterfall [
			_getCurrentApps

			(apps, next) ->
				debug "Current applications are #{JSON.stringify _.keys apps}"
				if ((_(groups).size() is 1) and _(groups).has "default")
					return next null, _getAppsToChange groups["default"], apps

				appsToChange = _getAppsToChange (_createGroupsMixin groups, deviceGroups), apps
				debug "Apps to be changed:", appsToChange
				next null, appsToChange

			(appsToChange, next) ->
				appsToBeInstalledNames = _(appsToChange.install).pluck "containerName"

				async.series [
					(cb) ->
						if _(appsToChange.install).isEmpty()
							log.info "No apps to be installed."
						_installApps appsToChange.install, cb

					(cb) ->
						if _(appsToChange.remove).isEmpty()
							log.info "No apps to be removed."
						_removeApps appsToChange.remove, cb
				], next

		], (error, result) ->
			if error
				state.publishLog "error", error
				log.error "Error during update: #{error.message}"

			log.info "Updating done."
			updating = false

			debug "Handle collections setting state to `idle`"
			state.setWork "idle"
			cb error, result

	_removeApps = (apps, cb) ->
		async.eachLimit apps, 1,
			(app, next) -> docker.removeContainer id: app, force: true, next
		, cb

	_installApps = (apps, cb) ->
		state.setWork "Updating applications..."

		async.eachLimit apps, 1,
			(appConfig, next) ->
				log.info "Installing #{appConfig.containerName}..."
				_installApp appConfig, next
		, cb

	_pastLastInstallStep = (currentStepName, endStepName) ->

		return false unless endStepName?

		_stepNameToNum = (step) ->
			num = 0
			switch step
				when "Pull"   then num = 1
				when "Clean"  then num = 2
				when "Create" then num = 3
				when "Start"  then num = 4
				else					     num = 0

		currentStep = _stepNameToNum currentStepName
		endStep     = _stepNameToNum endStepName

		return currentStep > endStep

	_installApp = (appConfig, cb) ->
		containerInfo =
			name: appConfig.containerName
			AttachStdin: !appConfig.detached
			AttachStdout: !appConfig.detached
			AttachStderr: !appConfig.detached
			Env: appConfig.environment
			Cmd: appConfig.entryCommand
			HostConfig:
				Binds: appConfig.mounts
				NetworkMode: appConfig.networkMode
				Privileged: appConfig.privileged
				RestartPolicy: { Name: appConfig.restartPolicy } # why 0?
				PortBindings: appConfig.ports
			Image: appConfig.fromImage
			Labels: appConfig.labels

		async.series [
			(next) ->
				return next () if _pastLastInstallStep("Pull", appConfig.lastInstallStep)

				docker.pullImage name: containerInfo.Image, (error) ->
					return next error if error
					log.info "Image #{containerInfo.Image} pulled correctly."
					next()
			(next) ->
				return next () if _pastLastInstallStep("Clean", appConfig.lastInstallStep)

				docker.getContainerByName containerInfo.name, (error, c) ->
					return next() if not c
					docker.removeContainer id: containerInfo.name, force: true, next
			(next) ->
				return next () if _pastLastInstallStep("Create", appConfig.lastInstallStep)

				docker.createContainer containerProps: containerInfo, next
			(next) ->
				return next () if _pastLastInstallStep("Start", appConfig.lastInstallStep)

				docker.startContainer id: containerInfo.name, next
		], (error, result) ->
				return cb error if error
				log.info "Application #{containerInfo.name} installed correctly!"
				cb()


	return {
		update
		isUpdating
		debouncedHandleCollection
		_createGroupsMixin # For testing purposes
		_getAppsToChange # For testing purposes
		_hasOutdatedApps # For testing purposes
	}
