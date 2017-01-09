process.title = 'servermock'

devicemqtt = require '@tn-group/device-mqtt'

process.on 'message', (config) ->
	server = devicemqtt config

	configurationsAction =
		action: 'storeConfiguration'

		payload:
			restartPolicy: "always"
			containerName: "ivh2-msgs"
			networkMode: "host"
			fromImage: "docker.viriciti.com/ivh2/ivh2-msgs"
			detached: true
			environment: [
				"NODE_ENV=development"
			]
			privileged: false
			version: "^1.0.0"
			mounts: [
				"/config/certs:/certs"
			]

		dest: 'viriciti'


	updateAppAction =
		action: 'updateApps'
		payload:
			"docker.viriciti.com/ivh2/ivh2-msgs": [
				"1.3.0"
				"1.3.1"
			]
		dest: 'viriciti'


	server.once 'connected', (socket) ->
		console.log "Forked client: #{config.clientId} connected!"
		process.send 'connected'

		process.once 'message', (action) ->
			if action is 'updateApps'
				socket.send(
					configurationsAction
				, (response) ->
						console.log 'Response: ', response

						socket.send(
							updateAppAction
						, (response) ->
								console.log 'Response: ', response
						)
				)



	server.connect()
