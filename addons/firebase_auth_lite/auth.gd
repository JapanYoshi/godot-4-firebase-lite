################################################################################
# The Firebase Auth service interface.
#
# Do not call this constructor directly. Instead, use `firebase.auth()`.
#
# NOTE: When (if) working on the OAuth providers, should probably model after
# an SDK other than JS (such as Unity or Java instead).  This because, namely,
# Godot is not a browser and cannot offer all of the same workflows.
#
#TODO: add the missing methods for handling custom out-of-band (OOB)
#      email and password confirmation/validation.
#
#TODO: support X-Firebase-Locale header for localizing email requests.
#
# https://firebase.google.com/docs/reference/js/firebase.auth
# https://firebase.google.com/docs/reference/js/firebase.auth.Auth
################################################################################
@icon("icon.svg")
extends Node
class_name FirebaseAuth

################################################################################
# ErrorUtil fake class.
#
const ErrorUtil = preload("error_util.gd")
################################################################################


# https://firebase.google.com/docs/reference/js/firebase.auth.Auth#onauthstatechanged
# https://firebase.google.com/docs/reference/js/firebase.auth.Auth#onidtokenchanged
# https://firebase.google.com/docs/reference/js/firebase.auth.Auth#updatecurrentuser
#TODO: consider expanding these to match the functionality of the error callback in JS (but doubt I will)
signal on_auth_state_changed(user)  # sign in, sign out (and update_current_user)
signal on_id_token_changed(user)    # sign in, sign out, id token refresh (and update_current_user)
# What about User.updateEmail and User.updatePassword?
# Nothing about this is documented in the User class doc but this other doc says
# such events will expire the refresh token (and ID token too, I suppose):
#   https://firebase.google.com/docs/auth/admin/manage-sessions

const URI_SECURE_TOKEN				: String = "https://securetoken.googleapis.com/v1/token?key="  # refresh token
const URI_SIGN_IN_WITH_CUSTOM_TOKEN	: String = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key="
const URI_SIGN_UP					: String = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key="  # includes anonymous
const URI_SIGN_IN_WITH_PASSWORD		: String = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="
const URI_SIGN_IN_WITH_IDP			: String = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key="  # sign in with oauth; link oauth
const URI_CREATE_AUTH_URI			: String = "https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key="  # fetch providers
const URI_SEND_OOB_CODE				: String = "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key="  # send pwd reset email; send email verif
const URI_RESET_PWD					: String = "https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key="  # verify; confirm
const URI_UPDATE					: String = "https://identitytoolkit.googleapis.com/v1/accounts:update?key="  # email; pwd; profile; link, unlink, conf email verif
const URI_LOOKUP					: String = "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key="  # get user
const URI_DELETE					: String = "https://identitytoolkit.googleapis.com/v1/accounts:delete?key="

var HEADERS_FORM : PackedStringArray = ["Content-Type: application/x-www-form-urlencoded"]
var HEADERS_JSON : PackedStringArray = ["Content-Type: application/json"]

# Success responses appear to include an undocumented "kind" field.
# I don't think we need them, but here are a few that have been observed:
#const KIND_SIGN_UP					: String = "identitytoolkit#SignupNewUserResponse"
#const KIND_SIGN_IN_WITH_PASSWORD	: String = "identitytoolkit#VerifyPasswordResponse"
#const KIND_LOOKUP					: String = "identitytoolkit#GetAccountInfoResponse"

#var app : FirebaseApp
var app : Node  # FirebaseApp (too circular to type this)
var current_user : FirebaseUser  # The currently signed-in user (or null).

var _http := HTTPRequest.new()
var json := JSON.new()

################################################################################
func _init(app : Node):
	self.app = app #as FirebaseApp
	add_child(_http)
	#not a node: #add_child(current_user)


################################################################################
# Handles the grunt work and error reporting of each REST API request.
#
func _auth_request(uri : String, headers : PackedStringArray, body : String) -> Object:
	var error = _http.request(
		uri + app._options.apiKey, headers, HTTPClient.METHOD_POST, body
	)
	if error == OK:
		var response = await _http.request_completed
		if response[0] == HTTPRequest.RESULT_SUCCESS:
			var rbody = response[3].get_string_from_utf8()
			var jpr = json.parse(rbody)
			if response[1] == HTTPClient.RESPONSE_OK:
				if jpr == OK:
					return FirebaseOk.new(json.data)
				else:
					push_error("Auth JSON parse error: " + str(json.get_error_line()) + ": " + json.get_error_message())
					return FirebaseError.new("http/response-parse-error")
			else:
				# https://firebase.google.com/docs/reference/rest/auth#section-error-format
				if jpr != OK:
					return FirebaseError.new(ErrorUtil.translate_error("auth", json.get_error_message()))
				else:
					push_error("Auth response error code: " + String(response[1]) + " " + rbody)
					return FirebaseError.new("http/response-error")
		else:
			push_error("Auth request result error codes: " + String(response[0]) + " " + String(response[1]))
			return FirebaseError.new("http/request-result-error")
	else:
		push_error("Auth request error code: " + String(error))
		return FirebaseError.new("http/request-error")


################################################################################
# Creates a new user account associated with the specified email address and password.
#
# Returns `FirebaseUser` or `FirebaseError`.
#
func create_user_with_email_and_password(email : String, password : String) -> Object:
	var body = json.stringify({
		"email" : email,
		"password" : password,
		"returnSecureToken" : true,
	})
	var result = await _auth_request(URI_SIGN_UP, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		current_user = FirebaseUser.new(
			self,
			result.localId,
			result.refreshToken,
			result.idToken,
			result.expiresIn
		)
		current_user.email = result.email
		#return current_user
		# Auto fetch all user data.
		return await _get_account_info_by_id_token(result.idToken, true)


################################################################################
# Signs in using an email and password.
#
# Returns `FirebaseUser` or `FirebaseError`.
#
func sign_in_with_email_and_password(email : String, password : String) -> Object:
	var body = json.stringify({
		"email" : email,
		"password" : password,
		"returnSecureToken" : true,
	})
	var result = await _auth_request(URI_SIGN_IN_WITH_PASSWORD, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		current_user = FirebaseUser.new(
			self,
			result.localId,
			result.refreshToken,
			result.idToken,
			result.expiresIn
		)
		current_user.email = result.email
		current_user.display_name = result.displayName
		# What to do with: result.registered ?  (It is not the same as emailVerified.)
		# Auto fetch all user data.
		return await _get_account_info_by_id_token(result.idToken, true)


################################################################################
# Signs in as an anonymous user.
#
# If there is already an anonymous user signed in, that user will be returned;
# otherwise, a new anonymous user identity will be created and returned.
#
# Returns `FirebaseUser` or `FirebaseError`.
#
func sign_in_anonymously() -> Object:
	var body = json.stringify({
		"returnSecureToken" : true,
	})
	var result = await _auth_request(URI_SIGN_UP, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		result = (result as FirebaseOk).data
		current_user = FirebaseUser.new(
			self,
			result.localId,
			result.refreshToken,
			result.idToken,
			result.expiresIn,
			true
		)
		# Note: result.email doesn't exist (even empty) even though doc says it does.
		# Auto fetch all user data.
		return await _get_account_info_by_id_token(result.idToken, true)


################################################################################
# Signs out the current user.
#
# Returns void.
#
func sign_out() -> void:
	if current_user:
		#current_user.free()  # for sure for sure  # ERROR: Can't free a Reference.
		current_user = null
		emit_signal("on_auth_state_changed", current_user)
		emit_signal("on_id_token_changed", current_user)


################################################################################
# Sends a password reset email to the given email address.
#
# The default password reset process is completed by firebaseapp.com's own service.
#
#TODO: If you have a custom email action handler, you can complete the
# password reset process by calling firebase.auth.Auth.confirmPasswordReset
# with the code supplied in the email sent to the user,
# along with the new password specified by the user.
#
#TODO: what about ActionCodeSettings?  Lite or not?
#      https://firebase.google.com/docs/reference/js/firebase.auth#actioncodesettings
#
# Returns OK or `FirebaseError`.
#
func send_password_reset_email(email : String) -> Object:
	var body = json.stringify({
		"requestType" : "PASSWORD_RESET",
		"email" : email,
	})
	var result = await _auth_request(URI_SEND_OOB_CODE, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		return FirebaseOk.new({})




################################################################################
################################################################################
################################################################################
# INTERNAL METHODS:
################################################################################


################################################################################
# Get the user's data.
#
# Internal method.
# Used to automatically fetch all data on sign on.
# If signing_in==true, also emits sign-on signals, and signs out on failure
# (because we just signed on).  [Maybe separate this mashup out.]
#
# Returns `FirebaseUser` or `FirebaseError`.
#
func _get_account_info_by_id_token(id_token : String, signing_in : bool = false) -> Object:
	var body = json.stringify({
		"idToken" : id_token,
	})
	var result = await _auth_request(URI_LOOKUP, HEADERS_JSON, body)
	if result is FirebaseError:
		if signing_in:
			sign_out()
		return result
	else:
		result = (result as FirebaseOk).data
		#print(result)
		result = result.users[0]
		#current_user.uid = result.localId  # ??? needed? or use to double check?
		current_user.email			= result.email			if result.has("email") else ""
		current_user.email_verified	= result.emailVerified	if result.has("emailVerified") else false
		current_user.display_name	= result.displayName	if result.has("displayName") else ""
		current_user.photo_url		= result.photoUrl		if result.has("photoUrl") else ""

		# Anon login doesn't return providerUserInfo (or much else).
		if result.has("providerUserInfo"):
			current_user.provider_data	= result.providerUserInfo #TODO: loop and clean (if I care)
			#if not result.providerUserInfo.empty():
			current_user.provider_id	= result.providerUserInfo[0].providerId
			if result.providerUserInfo[0].has("phoneNumber"):
				current_user.phone_number	= result.providerUserInfo[0].phoneNumber

		# Dunno why, but need to shorten deep refs like this for assignments.
		var meta = current_user.metadata
		meta.creation_time_secs		= result.createdAt as int / 1000
		meta.last_sign_in_time_secs	= result.lastLoginAt as int / 1000

		if signing_in:
			emit_signal("on_auth_state_changed", current_user)
			emit_signal("on_id_token_changed", current_user)
		return current_user


################################################################################
# Deletes and signs out the user.
#
# Internal method.  To be called from FirebaseUser class only.
#
# Returns OK or `FirebaseError`.
#
func _delete_current_user() -> Object:
	var body = json.stringify({
		"idToken" : current_user._IdTokenResult.token,
	})
	var result = await _auth_request(URI_DELETE, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		sign_out()
		return FirebaseOk.new({})


################################################################################
# Refreshes the current user, if signed in.
#
# Internal method.  To be called from FirebaseUser class only.
#
# Returns OK or `FirebaseError`.
#
func _reload_current_user() -> Object:
	var body = "grant_type=refresh_token" \
			+ "&refresh_token=" + current_user.refresh_token
	var result = await _auth_request(URI_SECURE_TOKEN, HEADERS_FORM, body)
	if result is FirebaseError:
#TODO: auto sign_out() on error or not? which errors??? certainly "auth/user-token-expired"  which funcs?  or make dev handle it?
		return result
	else:
		result = (result as FirebaseOk).data
		#current_user.uid = result.user_id  # ??? needed? or use to double check?
		current_user.refresh_token	= result.refresh_token
		current_user._set_id_token_result(result.id_token, result.expires_in as int, false)
		emit_signal("on_id_token_changed", current_user)
		result = await _get_account_info_by_id_token(result.id_token)
		if result is FirebaseError:
			return result
		else:
			return FirebaseOk.new({})


################################################################################
# Sends a verification email to a user.
#
# Internal method.  To be called from FirebaseUser class only.
#
# Returns OK or `FirebaseError`.
#
func _send_current_user_email_verification() -> Object:
	var body = json.stringify({
		"requestType" : "VERIFY_EMAIL",
		"idToken" : current_user._IdTokenResult.token,
	})
	var result = await _auth_request(URI_SEND_OOB_CODE, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		return FirebaseOk.new({})
#################################################################################
# Sends a verification email to a new email address.
#
# Internal method.  To be called from FirebaseUser class only.
#
# Returns OK or `FirebaseError`.
#
func _verify_before_update_current_user_email(new_email : String) -> Object:
	# NOTE: the REST form of this is not documented -- so guessing based on JS code here.
	var body = json.stringify({
		"requestType" : "VERIFY_AND_CHANGE_EMAIL",
		"idToken" : current_user._IdTokenResult.token,
		"newEmail" : new_email,
	})
	var result = await _auth_request(URI_SEND_OOB_CODE, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		return FirebaseOk.new({})


################################################################################
# Updates the user's email address.
#
# Internal method.  To be called from FirebaseUser class only.
#
# Returns OK or `FirebaseError`.
#
func _update_current_user_email(new_email : String) -> Object:
	var body = json.stringify({
		"idToken" : current_user._IdTokenResult.token,
		"email" : new_email,
		"returnSecureToken" : true,
	})
	var result = await _auth_request(URI_UPDATE, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		current_user.email			= result.email
		current_user.email_verified	= false         # ???
		current_user.provider_data	= result.providerUserInfo #TODO: loop and clean (if I care)
		current_user.provider_id	= result.providerUserInfo[0].providerId
		#current_user.uid = result.localId  # ??? needed? or use to double check?
		current_user.refresh_token	= result.refreshToken
		current_user._set_id_token_result(result.idToken, result.expiresIn as int, false)
		emit_signal("on_id_token_changed", current_user)
		return FirebaseOk.new({})


################################################################################
# Updates the user's password.
#
# Internal method.  To be called from FirebaseUser class only.
#
# Returns OK or `FirebaseError`.
#
func _update_current_user_password(new_password : String) -> Object:
	var body = json.stringify({
		"idToken" : current_user._IdTokenResult.token,
		"password" : new_password,
		"returnSecureToken" : true,
	})
	var result = await _auth_request(URI_UPDATE, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		current_user.provider_data	= result.providerUserInfo #TODO: loop and clean (if I care)
		current_user.provider_id	= result.providerUserInfo[0].providerId
		#current_user.uid = result.localId  # ??? needed? or use to double check?
		current_user.refresh_token	= result.refreshToken
		current_user._set_id_token_result(result.idToken, result.expiresIn as int, false)
		emit_signal("on_id_token_changed", current_user)
		return FirebaseOk.new({})


################################################################################
# Updates a user's profile data.
#
# Internal method.  To be called from FirebaseUser class only.
#
# Returns OK or `FirebaseError`.
#
func _update_current_user_profile(profile : Dictionary) -> Object:
	var b = {
		"idToken" : current_user._IdTokenResult.token,
		#"displayName" : null,
		#"photoUrl" : null,
		"deleteAttribute" : [],
		"returnSecureToken" : false,
	}

	var has_updates = false

	# Handle display_name change or wipe.
	if profile.has("display_name"):
		has_updates = true
		if profile.display_name == null:
			b.deleteAttribute.push_back("DISPLAY_NAME")
		else:
			b.displayName = profile.display_name

	# Handle photo_url change or wipe.
	if profile.has("photo_url"):
		has_updates = true
		if profile.photo_url == null:
			b.deleteAttribute.push_back("PHOTO_URL")
		else:
			b.photoUrl = profile.photo_url

	if not has_updates:
		push_error("Syntax error: FirebaseUser.update_profile() called without a dictionary containing 'display_name' and/or 'photo_url' keys.")
		# This was FAILED before, but the return type of Object prevents it from being an Error enum.
		# Yes, this is a misuse of the FirebaseError class, but I can't do better. -- Haley
		return FirebaseError.new("Syntax error: FirebaseUser.update_profile() called without a dictionary containing 'display_name' and/or 'photo_url' keys.")

	var body = json.stringify(b)
	var result = await _auth_request(URI_UPDATE, HEADERS_JSON, body)
	if result is FirebaseError:
		return result
	else:
		current_user.display_name	= result.displayName	if result.has("displayName") else ""
		current_user.photo_url		= result.photoUrl		if result.has("photoUrl") else ""
		current_user.provider_data	= result.providerUserInfo #TODO: loop and clean (if I care)
		current_user.provider_id	= result.providerUserInfo[0].providerId
		return FirebaseOk.new({})
