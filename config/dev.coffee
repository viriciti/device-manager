module.exports =
	mqtt:
		host: "localhost"
		port: 1883

	groups:
		path: "/home/dan/groups"

	docker:
		registry_auth:
			credentials:
				password: process.env.GL_ACCESS_TOKEN

	development: true
