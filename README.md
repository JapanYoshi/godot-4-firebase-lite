# ![Godot 4 Firebase Lite Logo](icon.svg) Godot 4 Firebase Lite

This project is a Godot 4 port of [Godot Firebase Lite](https://github.com/juanitogan/godot-firebase-lite), which supports [Firebase Realtime Database](https://firebase.google.com/products/realtime-database) only, and as such, also only supports RTDB.

Firebase Authentication can be done with email/password and anonymously.

Works on Godot 4.2.

### Origin and direction

Skip this section if you are bored already.

I've used the original Godot 3 add-on to make [Salty Trivia with Candy Barre](https://github.com/japanyoshi/salty), which is a trivia game that uses Firebase Realtime Database for its Jackbox-like phones-as-controllers backend. Thanks to the simplicity and ease of use of the original add-on, the implementation of this phones-as-controllers feature went smoothly.

But now that Godot 4.2 is out, it's time for me to consider developing my next project on Godot 4 instead. However, the add-on I found was clunky and hard to use, and did not behave as expected, with "update" erasing all keys I didn't update, for example.

Thank goodness for the MIT license, right? Since the original add-on was licensed under the MIT license, I can modify the plugin and distribute it over the Internet! Now I have an easy-to-use Firebase Realtime Database plugin for Godot 4, and you can use it too. Parts of this Readme are copied from the original Readme too.

Want to make this code (which is like 99% Juanito's and 1% my modifications to make it compliant with GDScript 4)? Yes, please!

Want to use some of this code for your own Firebase plugin with blackjack and hookers? Be my guest! I might even want to use that instead myself.

---

## Installation

1. Clone this repo, or download the zip of it.
2. Copy the `firebase_app_lite` folder into the `res://` folder of your game.  This is not an editor plugin, so it does not need to be in the `addons` folder if you have one, (and shouldn't be there if you want the class icons to display).
3. Also copy one or more of the following folders into the `res://` folder of your game, depending on the features you need (critical: place at the same level as `firebase_app_lite`):
    - `firebase_auth_lite`
    - `firebase_database_lite`
4. Create a `firebase` global namespace ([AutoLoad Singleton](https://docs.godotengine.org/en/stable/getting_started/step_by_step/singletons_autoload.html#autoload)) by going into Project Settings > AutoLoad tab, and add a new entry with the following settings:
    - Path: `res://firebase_app_lite/firebase.gd` (or wherever you put it)
    - Name: `firebase` (note this is all lower case -- if you try proper case it will generate a conflict error with the `Firebase` class [Godot's style guide is mixed up about class instances])
    - Singleton: [x] Enable

Or, maybe check Godot's AssetLib, copy the packages in from there, and then enable the singleton.

##  Usage

### Initialization

Copy the config from your Firebase Project Settings > Web App, and adapt it from JavaScript to GDScript (quote the key names or replace colons with equals signs):

```gdscript
# Set the configuration options for your app.
# TODO: Replace with your project's config object.
var firebase_config = {
    "apiKey": "",  # If you don't need auth, you don't need this.
    "authDomain": "your-awesome-app.firebaseapp.com",
    "databaseURL": "https://your-awesome-app-db.region-maybe.firebaseio.com",
    "projectId": "your-awesome-app",
    "storageBucket": "your-awesome-app.appspot.com",
    "messagingSenderId": "111111111111",
    "appId": "1:111111111111:web:aaaaaaaaaaaaaaaaaaaaaa"
}
# Initialize Firebase
firebase.initialize_app(firebase_config)

# Get a reference to the database service.
var db : FirebaseDatabase = firebase.database()
```

### Read and write data

To manipulate data you must first get a [reference](docs/database.md#firebasereference-class) to a path in the database that you want to manipulate:

```gdscript
var ref : FirebaseReference = db.get_reference_lite("some/path/to/data")
```

You should always use `get_reference_lite()` instead of `get_reference()` if not using [Firebase array fakies](https://firebase.googleblog.com/2014/04/best-practices-arrays-in-firebase.html) (and you shouldn't be using them).  Array fakies are a headache to code for behind the scenes.  If you do use array fakies, the lite version of this method still supports them somewhat (as whole objects) in case that fits your use case for them.  Otherwise, the heavier version makes a good effort in supporting array fakies in all sorts of crazy ways... but testing it fully has exhausted me a bit too much for a feature I don't need.  Too many edge cases.  Maybe someone with a bigger brain will tackle it harder (or rewrite it the lazier-but-slower way).

After you get a ref to a node, you can start issuing [CRUD methods](docs/database.md#ref-methods) against it.

Godot Firebase Lite promotes the pattern of using `await()` for all of the CRUD methods (which saves a lot of signal wiring).  This is a similar pattern to using `.then()` in JavaScript even though the resulting code looks quite different.  For example:

JavaScript:
```javascript
ref.update({"name": "Pelé"}).then(() => {
    console.log("Yay!");
}).catch((error) => {
    console.error("Oops!", error);
})
```

GDScript:
```gdscript
# This will return either a FirebaseError or a FirebaseOk object.
var result = await ref.update({"name": "Pelé"})
if result is FirebaseError:
    printerr("Oops! ", str(result))
else:
    print("Yay!")
```

Signaling still plays a big role in this tool but it is primarily used for triggering the same [SSE](https://www.w3.org/TR/eventsource/) listener events that other Firebase SDKs trigger.

### Listening to data changes

You can listen for [data-change events](docs/database.md#signals) by turning on a ref's listener:

```gdscript
ref.child_added.connect(_do_something)
ref.child_changed.connect(_do_something_else)
ref.child_removed.connect(_do_something_elser)
ref.enable_listener()
```

Like shown above, you can skip the await on `enable_listener()` if you don't need to wait for initial signaling to finish.
Signals can be connected before or after enabling the listener, depending on your needs.
Note that enabling a listener will trigger a `"child_added"` signal for each existing child, followed by a single `"value_changed"` signal.
If you don't need these initial `"child_added"` signals, connect the `"child_added"` signal after `enable_listener()` has finished (by awaiting it, or by connecting and waiting for that first `"value_changed"` signal).

### Auth

If you need to enable the auth service, make a call to `firebase.auth()`.  From there, call the [auth methods](docs/auth.md#methods) you need.  For example:

```gdscript
# Get a reference to the auth service.
var auth : FirebaseAuth = firebase.auth()

# Sign a user in.
var result = await auth.sign_in_with_email_and_password(email, password)
if result is FirebaseError:
    print(result.code)
else:
    var user = result as FirebaseUser
    print(user.email)
```

Currently, only email/password and anonymous authentications are supported -- and only by Firebase's built-in email/password handler.

### Type casting

Due to various limitations and/or nuances with GDScript, precise typing of the return objects from many methods in this SDK is not possible.  Thus, if you want better autocompletion with some variables, you will need to cast them as their specific type yourself.  For example:

```gdscript
var db = firebase.database() as FirebaseDatabase
```

or

```gdscript
var db: FirebaseDatabase = firebase.database()
```

Note that pre-typing is not sufficient.  For example, this **does not** result in a properly-cast `db` variable:

```gdscript
var db: FirebaseDatabase
db = firebase.database()
```

When and what to cast to is indicated in the reference docs by a type (or types) in parenthesis next to the actual type.  For example: `Node` (`FirebaseDatabase`) indicates the actual type is `Node` but you _should_ cast it as `FirebaseDatabase` if you plan on working with it much.

Obviously, simple types like `FirebaseOk` and even `FirebaseError` don't need casting considering their simplicity and their short lifetime.

---

## Reference manual

- [FirebaseAppLite Reference](docs/app.md)
- [FirebaseAuthLite Reference](docs/auth.md)
- [FirebaseDatabaseLite Reference](docs/database.md)

### More help

This readme assumes you already know how to use Realtime Database and Authentication from using one of the other language SDKs.

For details not covered here -- and there are many things I simply don't have time to re-document here -- these docs for the JavaScript SDK should help (these are where I first learned how to use Realtime Database before writing this package):

- https://firebase.google.com/docs/database/web/start  (a bit outdated)
- https://firebase.google.com/docs/database/admin/start  (a bit outdated)
- https://firebase.google.com/docs/reference/js
- https://firebase.google.com/docs/reference/js/firebase.database.Reference
- https://firebase.google.com/docs/auth/web/start

### Differences from the JavaScript SDK

As the name suggests, Godot Firebase Lite is not nearly as feature-complete as, say, the JS SDK.  Not even close.  The bits that _are_ here, however, seem to cover the most likely use-cases well.  Building a full version looks like it might require 40x the code... and I only need a tool that is merely good enough.

Primarily, anything related to priority data, ordering, filtering, and transactions (ETags), is not here.  Some of that you can do in GDScript if you need it.  Some of that may be added in the future.

For detailed differences from the JS SDK, see the items at the bottom of each class reference.
