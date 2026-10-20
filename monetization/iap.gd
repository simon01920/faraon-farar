class_name Iap
extends RefCounted
## Purchase facade: turns a StoreBackend's raw purchase/restore events into the
## premium entitlement stored in MonetizationStore, and exposes store-localized
## product info to the UI. Instantiate one when the purchase screen opens,
## connect its signals, and free it when done. Static helpers cover the
## app-startup re-validation that has no UI.
##
## Two products, both remove ALL ads:
##   * yearly subscription (auto-renewable) — premium until its expiry;
##   * lifetime non-consumable — premium forever, offline included.
## Restore purchases re-applies either from the store (Apple requires it).

signal products_updated(products: Array)
signal purchased(product_id: String)
signal purchase_failed(reason: String)
signal restored(count: int)

const PRODUCT_YEARLY := StoreBackend.PRODUCT_YEARLY
const PRODUCT_LIFETIME := StoreBackend.PRODUCT_LIFETIME

var backend: StoreBackend
## Backend used by the startup re-validation (refresh_entitlements), held
## for the whole session so its asynchronous answer can still arrive.
static var _revalidation_backend: StoreBackend
## Latest store-localized product info, id -> {"price", "kind"}.
var _products := {}


func _init(store_backend: StoreBackend = null) -> void:
	backend = store_backend if store_backend != null else StoreBackend.MockStoreBackend.new()
	# Method callables only: a lambda using `self` holds a strong reference to
	# this RefCounted, and the backend (which we own) holding that lambda made
	# an Iap <-> backend cycle that leaked both every time the store opened.
	backend.products_updated.connect(_on_products)
	backend.purchase_completed.connect(_on_purchase_completed)
	backend.purchase_failed.connect(_on_purchase_failed)
	backend.restore_finished.connect(_on_restore_finished)


func query_products() -> void:
	backend.query_products()


## Store-localized price string for a product, or "" if not loaded yet. The UI
## must show THIS (regional currency), never a hardcoded amount.
func price_of(product_id: String) -> String:
	return str(_products.get(product_id, {}).get("price", ""))


func purchase(product_id: String) -> void:
	backend.purchase(product_id)


func restore_purchases() -> void:
	backend.restore_purchases()


func _on_products(products: Array) -> void:
	_products.clear()
	for p in products:
		if p is Dictionary and p.has("id"):
			_products[p["id"]] = p
	products_updated.emit(products)


func _on_purchase_completed(product_id: String, kind: String, valid_until: int) -> void:
	_apply_entitlement(kind, valid_until)
	purchased.emit(product_id)


func _on_purchase_failed(_product_id: String, reason: String) -> void:
	purchase_failed.emit(reason)


func _on_restore_finished(count: int) -> void:
	restored.emit(count)


static func _apply_entitlement(kind: String, valid_until: int) -> void:
	match kind:
		"lifetime":
			MonetizationStore.set_lifetime()
		"subscription":
			# Doživotné premium je navždy — predplatné (nové, obnovené zo
			# starej účtenky či už vypršané) ho nikdy nesmie prepísať.
			if MonetizationStore.premium_kind() == "lifetime":
				return
			# Staršia účtenka (restore) neskracuje už známu platnosť.
			var known := 0
			if MonetizationStore.premium_kind() == "subscription":
				known = MonetizationStore.premium_until()
			MonetizationStore.set_subscription(maxi(valid_until, known))


## Startup re-validation (no UI). Lifetime is trusted offline forever; an active
## subscription is trusted from the local cache and only asked to re-validate
## against the store — never flipped off on a single failed/absent check, so a
## brief outage or offline launch does not strip premium (grace behaviour).
static func refresh_entitlements(store_backend: StoreBackend = null) -> void:
	if MonetizationStore.premium_kind() != "subscription":
		return
	var backend := store_backend
	if backend == null:
		backend = StoreBackend.MockStoreBackend.new()
	# A real store answers asynchronously: keep the backend referenced until
	# then (a local variable alone was freed when this function returned, so
	# the renewal callback could never arrive).
	if _revalidation_backend != backend:
		_revalidation_backend = backend
		backend.purchase_completed.connect(func(_id, kind, until):
			_apply_entitlement(kind, until))
	# A real backend re-queries and, if the sub lapsed at the store, calls
	# clear_premium via its own flow; the mock leaves the cache intact.
	backend.validate_subscription(MonetizationStore.premium_until())
