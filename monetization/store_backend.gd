class_name StoreBackend
extends RefCounted
## The boundary between our IAP facade (Iap) and the platform billing plugin.
## Everything above stays plugin-free and testable; a concrete subclass wraps
## Google Play Billing (Android) / StoreKit 2 (iOS), or the recommended
## cross-platform OpenIAP plugin. Default is MockStoreBackend so the game runs
## and the purchase UI works with no plugin present. See STORE_SETUP.md.
##
## Product ids (both remove ALL ads):
##   faraon_remove_ads_yearly    — auto-renewable subscription, 6,99 €/yr
##   faraon_remove_ads_lifetime  — non-consumable, 14,99 € forever

const PRODUCT_YEARLY := "faraon_remove_ads_yearly"
const PRODUCT_LIFETIME := "faraon_remove_ads_lifetime"
const PRODUCT_IDS := [PRODUCT_YEARLY, PRODUCT_LIFETIME]

## Product metadata arrived: Array of
##   {"id": String, "price": String (store-localized), "kind": "sub"|"lifetime"}
signal products_updated(products: Array)
## A purchase (or restore) granted entitlement:
##   product_id, kind ("subscription"|"lifetime"), valid_until (unix, 0=forever)
signal purchase_completed(product_id: String, kind: String, valid_until: int)
signal purchase_failed(product_id: String, reason: String)
## Restore finished (whether or not anything was found).
signal restore_finished(restored_count: int)


func query_products() -> void:
	products_updated.emit([])


func purchase(product_id: String) -> void:
	purchase_failed.emit(product_id, "not_supported")


func restore_purchases() -> void:
	restore_finished.emit(0)


## Re-validate a cached subscription against the store (called at startup).
## Real backends query the current entitlement; the mock trusts the cache.
func validate_subscription(_cached_until: int) -> void:
	pass


class MockStoreBackend:
	extends StoreBackend
	## Dev/test double: instant success with fake store-localized prices so the
	## purchase UI and premium flow can be exercised without a real store.
	const YEAR_SECONDS := 365 * 24 * 60 * 60

	func query_products() -> void:
		products_updated.emit([
			{"id": PRODUCT_YEARLY, "price": "6,99 €", "kind": "sub"},
			{"id": PRODUCT_LIFETIME, "price": "14,99 €", "kind": "lifetime"},
		])

	func purchase(product_id: String) -> void:
		match product_id:
			PRODUCT_YEARLY:
				var until := int(Time.get_unix_time_from_system()) + YEAR_SECONDS
				purchase_completed.emit(product_id, "subscription", until)
			PRODUCT_LIFETIME:
				purchase_completed.emit(product_id, "lifetime", 0)
			_:
				purchase_failed.emit(product_id, "unknown_product")

	func restore_purchases() -> void:
		# Mock has nothing server-side to restore; real backends re-grant here.
		restore_finished.emit(0)
