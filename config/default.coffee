os = require "os"

module.exports =
	host: os.hostname()

	mqtt:
		host: "device-manager.viriciti.com"
		port: 8883
		tls:
			key:  "/certs/ivh.key"
			cert: "/certs/ivh.crt"
			ca:   "/certs/ca.crt"
		clientId: os.hostname()
		extraOpts:
			keepalive: 60
			rejectUnauthorized: true
			reconnectPeriod: 5000

	devicemqtt:
		queueTimeout: 5000 # never touch it

	groups:
		path: "/groups"
		mqttTopic: "global/collections/groups"
		whiteList: ["device-manager", "dev"]

	# in minutes
	cronJob: 5

	sendStateThrottleTime: 10000

	osUpdater:
		topic: "enabledOsVersion"
		host:  "localhost"
		port:  3003

	docker:
		layer:
			regex: /(\/(var\/lib\/)?docker\/image\/overlay2\/layerdb\/sha256\/[\w\d]+)/
			maxPullRetries: 5
		socketPath: "/var/run/docker.sock"
		maxRetries: 5
		registry_auth:
			required: true
			credentials:
				username: "device-user"
				password: process.env.DOCKER_REGISTRY_TOKEN # Create one in your profile at git.viriciti.com
				email: "device-user@viriciti.com"
				serveraddress: "https://index.docker.io/v1"

	development: false
