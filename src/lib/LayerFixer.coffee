{ Writable } = require "stream"

class LayerFixer extends Writable
	constructor: (@regex) ->
		super objectMode: true

	write: (data, enc, cb) =>
		return cb() unless data.error

		conflictingDirectory = @regex.exec data.error
			.shift()
			.trim()

		return cb new Error data.error unless conflictingDirectory

		error = new Error "Removing conflicting directory: #{conflictingDirectory}"
		error.conflictingDirectory = conflictingDirectory

		cb error

module.exports = LayerFixer
