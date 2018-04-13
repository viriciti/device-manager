debug = (require "debug") "app:docker-logs"

log = (require "../lib/Logger") "DockerLogsParser"

###
The DockerLogsParser class parses the events messages
coming from the docker daemon activity.
Currently, is not possible to parse correctly the delete
image and destroy container events,
since the information about images and containers
are no longer available after removing them.
###

class DockerLogsParser
	constructor: (@docker) ->

	parseLogs: (logs) =>
		if (logs.status is "die")
			return @_handleDyingContainer logs

		switch logs.Type
			when "image"
				switch logs.Action
					when "pull" then @_handlePullImageLogs logs
					when "untag" then @_handleUntagImageLogs logs
					when "tag" then @_handleTagImageLogs logs
					when "delete" then @_handleDeleteImageLogs logs
			when "container"
				switch logs.Action
					when "create" then @_handleCreateContainerLogs logs
					when "start" then @_handleStartContainerLogs logs
					when "stop" then @_handleStopContainerLogs logs
					when "destroy" then @_handleDestroyContainerLogs logs




	_handlePullImageLogs: (logs) ->
		image = logs.Actor.ID
		time = logs.time
		return { message: "Pulled image #{image}", time }

	_handleUntagImageLogs: (logs) ->
		imageID = (logs.Actor.ID.split ":")[1]
		time = logs.time
		return { message: "An image has been untagged", time }

	_handleTagImageLogs: (logs) ->
		image = (logs.Actor.Attributes.name.split ":")[0]
		imageTag = (logs.Actor.Attributes.name.split ":")[1]
		time = logs.time
		return { message: "Tagged image #{image} with tag #{imageTag}", time}

	_handleDeleteImageLogs: (logs) ->
		imageID = (logs.Actor.ID.split ":")[1]
		time = logs.time
		return { message: "An image has been removed", time }

	_handleStartContainerLogs: (logs) ->
		containerName = logs.Actor.Attributes.name
		time = logs.time
		return { message: "Started container #{containerName}" , time }

	_handleCreateContainerLogs: (logs) ->
		fromImage = logs.Actor.Attributes.image
		containerName = logs.Actor.Attributes.name
		time = logs.time
		return {
			message: "Created container #{containerName} from image #{fromImage}"
			time
		}

	_handleStopContainerLogs: (logs) ->
		containerName = logs.Actor.Attributes.name
		time = logs.time
		return { message: "Stopped container #{containerName}", time }

	_handleDestroyContainerLogs: (logs) ->
		time = logs.time
		return { message: "A container has been destroyed", time }


	_handleDyingContainer: (logs) ->
		time = logs.time
		return { message: "Container #{logs.Actor.Attributes.name} has died!", time, type: "warning" }

module.exports = DockerLogsParser
