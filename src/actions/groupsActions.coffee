_      = require "underscore"
async  = require "async"
config = require "config"
debug  = (require "debug") "app:actions:groups"
fs     = require "fs"

log = (require "../lib/Logger") "groups actions"

module.exports = (state, appUpdater) ->
	storeGroup = (label, cb) ->
		log.info "Storing group `#{label}` in `#{config.groups.path}`"

		fs.readFile config.groups.path, (error, file) ->
			if error
				log.error "Error reading file: #{error.message}"
			else
				debug "File read."

			currentGroups = JSON.parse file.toString()
			groupCurrentIndex = _(currentGroups).keys().length

			debug "Current groups: #{file.toString()}, index #{groupCurrentIndex}"

			if _.contains _(currentGroups).values(), label
				log.warn "Group #{label} already there. Skipping groups creation..."
				return cb()

			newGroup = {}
			newGroup[++groupCurrentIndex] = label

			newGroupsFile = "#{JSON.stringify _.extend currentGroups, newGroup}\n"
			debug "Writing file: #{newGroupsFile}"

			async.series [
				(next) ->
					debug "Fs write file"
					fs.writeFile config.groups.path, newGroupsFile, next
				(next) ->
					debug "Calling app updater update"
					appUpdater.update state.getGlobalGroups(), state.getGroups(), next
			], (error) ->
				if error
					log.error "Error in `storeGroup` action: #{error.message}"

				debug "Store groups setting state to `idle`"
				state.setWork "idle"
				cb error, "New group file generated correctly with new label #{label}"


	storeGroups = (labels, cb) ->
		log.info "Storing groups", labels

		async.waterfall [
			(next) ->
				debug "Reading from `#{config.groups.path}`"
				fs.readFile config.groups.path, (error, file) ->
					if error
						log.error "Error reading file: #{error.message}"
					else
						debug "File read."

					currentGroups = JSON.parse file.toString()
					groupCurrentIndex = _(currentGroups).keys().length

					debug "Current groups: #{file.toString()}, index #{groupCurrentIndex}"

					newGroups =
						_(labels).reduce (groups, label, index) ->
							if _.contains _(currentGroups).values(), label
								log.warn "Group test is already present. Skipping..."
								return groups

							group = {}
							groupCurrentIndex = groupCurrentIndex + 1
							group[groupCurrentIndex] = label
							_(groups).extend groups, group
						, {}

					newGroupsFile = "#{JSON.stringify _.extend currentGroups, newGroups}\n"
					debug "Writing file: `#{newGroupsFile}`"
					next null, newGroupsFile

			(newGroupsFile, nextnext) ->
				async.series [
					(next) ->
						debug "Fs write file to `#{config.groups.path}`"
						fs.writeFile config.groups.path, newGroupsFile, next
					(next) ->
						debug "Calling app updater update"
						appUpdater.update state.getGlobalGroups(), state.getGroups(), next
				], nextnext

		], (error) ->
			if error
				log.error "Error in `storeGroups` action: #{error.message}"
				return cb error

			debug "Store groups setting work to `idle`"
			state.setWork "idle"
			cb null, "New group file generated correctly with labels #{labels.join ", "}"


	removeGroup = (label, cb) ->
		log.info "Removing groups", label

		async.waterfall [
			(next) ->
				debug "Reading from `#{config.groups.path}`"
				fs.readFile config.groups.path, (error, file) ->
					if error
						log.error "Error reading file: #{error.message}"
						return next error
					else
						debug "File read."

					currentGroups = JSON.parse file.toString()
					next null, (_shiftGroups currentGroups, label)

			(newGroupsFile, nextnext) ->
				newGroupsFile = "#{JSON.stringify newGroupsFile}\n"
				async.series [
					(next) ->
						debug "Fs write file to `#{config.groups.path}`"
						fs.writeFile config.groups.path, newGroupsFile, next
					(next) ->
						debug "Calling app updater update"
						appUpdater.update state.getGlobalGroups(), state.getGroups(), next
				], nextnext
		], (error) ->
			if error
				log.error "Error in `removeGroup` action: #{error.message}"
				return cb error

			debug "Remove group setting work `idle`"
			state.setWork "idle"

			cb null, "Group #{label} removed correctly!
				The device will adjust to the new groups configuration"




	_shiftGroups = (groups, groupToRemove) ->
		newGroups = _.chain(groups)
			.values()
			.without groupToRemove
			.value()

		_(newGroups).reduce (groupsObj, group, index) ->
			groupsObj[++index] = group
			groupsObj
		, {}

	return {
		storeGroup
		storeGroups
		removeGroup
	}