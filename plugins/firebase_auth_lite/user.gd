################################################################################
# A Firebase user account.
#
# MJJ: Look into refreshing and keep-alive best practices.
# https://firebase.google.com/docs/auth/admin/manage-sessions
# ID tokens: 1 hour.  Refresh tokens: forever until critical event.
# Provide refresh function (`reload()`) and token expiration data so user can
# keep alive how they choose.
#
# https://firebase.google.com/docs/reference/js/firebase.User
################################################################################
@icon("icon.svg")
extends RefCounted
class_name FirebaseUser

################################################################################
# IdTokenResult fake class.
#
# https://firebase.google.com/docs/reference/js/firebase.auth.IDTokenResult
###

var json := JSON.new()
# Changed const to var because you assign a value to it. -- Haley
var _IdTokenResult = {
	"token": null,					# The Firebase Auth ID token JWT string.
	"expiration_interval_secs":3600,# seconds; not in JS; Firebase always expires in 1 hour
	#"auth_time": null,				# UTC string; to never do, I suspect
	#"issued_at_time": null,		# UTC string; to never do, I suspect
	#"expiration_time": null,		# UTC string; to never do, I suspect
	"auth_time_secs": null,			# int; OS epoch time in seconds; This is the time the user authenticated (signed in) and not the time the token was refreshed.
	"issued_at_time_secs": null,	# int; OS epoch time in seconds; The ID token issued-at time.
	"expiration_time_secs": null,	# int; OS epoch time in seconds; The ID token expiration time.
#	"sign_in_provider": null,		# string; null; Note, this does not map to provider IDs. ???
#	"sign_in_second_factor": null,	# string; null
	#"claims": {},					# to never do, I suspect
}
func _set_id_token_result(token : String, expires_in : int, new_auth : bool = false) -> void:
	_IdTokenResult.token = token
	_IdTokenResult.expiration_interval_secs = expires_in
	# Is this what OS.get_system_time_secs() translates to in GDScript 4?
	# It's used several times throughout this script. -- Haley
	_IdTokenResult.issued_at_time_secs = int(Time.get_unix_time_from_system())
	_IdTokenResult.expiration_time_secs = _IdTokenResult.issued_at_time_secs + expires_in
	if new_auth:
		_IdTokenResult.auth_time_secs = _IdTokenResult.issued_at_time_secs
################################################################################

################################################################################
# UserMetadata fake class.
#
# https://firebase.google.com/docs/reference/js/firebase.auth.UserMetadata
const metadata = {
	#"creation_time": null,			# UTC string (optional); to never do, I suspect
	#"last_sign_in_time": null,		# UTC string (optional); to never do, I suspect
	"creation_time_secs": null,		# int (optional); OS epoch time in seconds
	"last_sign_in_time_secs": null,	# int (optional); OS epoch time in seconds
}
################################################################################

#var _auth				: FirebaseAuth
var _auth				: Node		# FirebaseAuth (too circular to type this)

var display_name		: String	# null
var email				: String	# null
var email_verified		: bool		= false
var is_anonymous		: bool
var phone_number		: String	# null
var photo_url			: String	# null
var provider_data		: Array		# TODO: UserInfo[] class fake (if I care)
var provider_id			: String
var refresh_token		: String
var uid					: String


################################################################################
func _init(
	auth			: Node,	# auth parent
	uid				: String,
	refresh_token	: String,
	id_token		: String,
	expires_in		: String,
	is_anonymous	: bool = false
):
	_auth = auth
	self.uid = uid
	self.refresh_token = refresh_token
	_set_id_token_result(id_token, expires_in as int, true)
	self.is_anonymous = is_anonymous


################################################################################
func _to_string() -> String:
	return "display_name: %s\n"		% display_name		\
		+ "email: %s\n"				% email				\
		+ "email_verified: %s\n"	% email_verified	\
		+ "is_anonymous: %s\n"		% is_anonymous		\
		+ "metadata: %s\n"			% json.stringify(metadata)	\
		+ "phone_number: %s\n"		% phone_number		\
		+ "photo_url: %s\n"			% photo_url			\
		+ "refresh_token: %s\n"		% refresh_token		\
		+ "uid: %s\n"				% uid				\
		+ "IdTokenResult: %s\n"		% json.stringify(_IdTokenResult, "  ", true)


################################################################################
# Deletes and signs out the user.
#
# Returns OK or `FirebaseError`.
#
func delete() -> Object:
	return await _auth._delete_current_user()


################################################################################
# Returns a JSON Web Token (JWT) used to identify the user to a Firebase service.
#
# Returns the current token if it has not expired. Otherwise, this will
# refresh the token and return a new one.
#
# force_refresh: boolean - Force refresh regardless of token expiration.
#
# Returns a JWT `String` or `FirebaseError`.
#
func get_id_token(force_refresh : bool = false) -> Object:
	if force_refresh or _IdTokenResult.expiration_time_secs <= int(Time.get_unix_time_from_system()):
		var result = await reload()
		if result is FirebaseError:
			return result
	else:
		# Turns out, to be yieldable, you need to ALWAYS... EITHER yield to
		# something else, OR return an Object.
		#TODO: This is an annoying hack! Find a better way.
		#      I tried to build my own dummy func to yield to (or resume from) but failed.
		await _auth.get_tree().create_timer(0).timeout
	return _IdTokenResult.token


################################################################################
# Returns an IdTokenResult dictionary (fake class).
#
# force_refresh: boolean - Force refresh regardless of token expiration.
#
# Returns an IdTokenResult `Dictionary` or `FirebaseError`.
#
###
# Removed the return type because Dictionary is (apparently) no longer an Object. -- Haley
func get_id_token_result(force_refresh : bool = false):
	if force_refresh:
		var result = await reload()
		if result is FirebaseError:
			return result
	else:
		# Turns out, to be yieldable, you need to ALWAYS... EITHER yield to
		# something else, OR return an Object.
		#TODO: This is an annoying hack! Find a better way.
		#      I tried to build my own dummy func to yield to (or resume from) but failed.
		await _auth.get_tree().create_timer(0).timeout
	return _IdTokenResult.duplicate(true)


################################################################################
# Refreshes the current user, if signed in.
#
# Returns OK or `FirebaseError`.
#
func reload() -> Object:
	return await _auth._reload_current_user()


################################################################################
# Sends a verification email to a user.
#
# The default verfication process is completed by firebaseapp.com's own service.
#
#TODO: If you have a custom email action handler, you can complete the
# verification process by calling firebase.auth.Auth.applyActionCode.
#
#TODO: what about ActionCodeSettings?  Lite or not?
#      https://firebase.google.com/docs/reference/js/firebase.auth#actioncodesettings
#
# Returns OK or `FirebaseError`.
#
func send_email_verification() -> Object:
	return await _auth._send_current_user_email_verification()
################################################################################
# Sends a verification email to a new email address.
# The user's email will be updated to the new one after being verified.
#
# The default verfication process is completed by firebaseapp.com's own service.
#
#TODO: If you have a custom email action handler, you can complete the
# verification process by calling firebase.auth.Auth.applyActionCode.
#
#TODO: what about ActionCodeSettings?  Lite or not?
#      https://firebase.google.com/docs/reference/js/firebase.auth#actioncodesettings
#
# Returns OK or `FirebaseError`.
#
func verify_before_update_email(new_email : String) -> Object:
	return await _auth._verify_before_update_current_user_email(new_email)


################################################################################
# Updates the user's email address.
#
# An email will be sent to the original email address (if it was set) that
# allows to revoke the email address change, in order to protect them from
# account hijacking.
#
# Important: this is a security sensitive operation that requires the user
# to have recently signed in.
#TODO: If this requirement isn't met, ask the user to authenticate again and then
# call firebase.User.reauthenticateWithCredential.
#
# Returns OK or `FirebaseError`.
#
func update_email(new_email : String) -> Object:
	return await _auth._update_current_user_email(new_email)


################################################################################
# Updates the user's password.
#
# Important: this is a security sensitive operation that requires the user
# to have recently signed in.
#TODO: If this requirement isn't met, ask the user to authenticate again and then
# call firebase.User.reauthenticateWithCredential.
#
# Returns OK or `FirebaseError`.
#
func update_password(new_password : String) -> Object:
	return await _auth._update_current_user_password(new_password)


################################################################################
# Updates the user's phone number.
#
# Returns OK or `FirebaseError`.
#TODO:
#func update_phone_number(phone_credential : AuthCredential) -> Object:
#func update_phone_number(provider_id : String, sign_in_method : String) -> Object:
#	return await _auth._update_current_user_phone_number(phone_credential)


################################################################################
# Updates a user's profile data.
#
# **profile:** { **display_name:** _String_ | _null_; **photo_url:** _String_ | _null_ }
# - The profile's display_name and photo_url to update.
#   - **display_name:** _String_ | _null_ (optional). Set to `null` to delete current value.
#   - **photo_url:** _String_ | _null_ (optional). Set to `null` to delete current value.
# - Example: `{"display_name": "Super Dave", "photo_url": "http://placekitten.com/100/100"}`
#
# Returns OK or `FirebaseError`.
#
#func update_profile(display_name : String = char(0), photo_url : String = char(0)) -> Object:
	# Ugh, char(0) is such a hack for overloading.
	#TODO: consider splitting into two methods (downside: more traffic... but so what?)
func update_profile(profile : Dictionary) -> Object:
	return await _auth._update_current_user_profile(profile)
