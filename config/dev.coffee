module.exports =
	mqtt:
		host: "localhost"
		port: 1883

	groups:
		path: "/home/dan/groups"

	docker:
		registry_auth:
			credentials:
				password: process.env.GITLAB_ACCESS_TOKEN # Create one in your profile at git.viriciti.com

	development: true
