extends SceneTree
## Dev-only probe: banner v menu (free), sekcia „Odstrániť reklamy" v
## nastaveniach s cenami zo store, a že po nákupe banner zmizne.
## Run: godot --path . -s res://tools/monetization_probe.gd


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://tools/%s.png" % name))
	print("saved ", name)


func _initialize() -> void:
	# Čistý štart: žiadne premium, čerstvé reklamné okno.
	MonetizationStore.clear_premium()
	MonetizationStore.set_ad_state(AdPolicy.fresh_state())
	MonetizationStore.set_interstitial_pending(false)
	change_scene_to_file("res://scenes/main.tscn")
	_run()


func _run() -> void:
	while current_scene == null:
		await process_frame
	root.size = Vector2i(1280, 720)
	await create_timer(0.6).timeout
	var main := current_scene
	print("banner viditeľný (free, menu): ", main._banner.visible,
			" (očakávané true)")
	_snap("probe_money_menu_banner")

	# Nastavenia — sekcia Odstrániť reklamy s dvomi produktmi a cenami.
	var menu: MainMenu = main._current_screen
	menu._menu_screen.visible = false
	menu._settings_screen.visible = true
	await create_timer(0.5).timeout
	_snap("probe_money_settings")

	# Simuluj nákup lifetime cez mock IAP -> premium, banner zmizne.
	menu._ensure_iap()
	menu._iap.purchase(Iap.PRODUCT_LIFETIME)
	await create_timer(0.4).timeout
	print("premium po nákupe: ",
			MonetizationStore.is_premium(int(Time.get_unix_time_from_system())),
			" (očakávané true)")
	menu._settings_screen.visible = false
	menu._menu_screen.visible = true
	main._refresh_banner()
	await create_timer(0.3).timeout
	print("banner viditeľný po nákupe: ", main._banner.visible,
			" (očakávané false)")
	_snap("probe_money_premium")

	# Uprac po sebe.
	MonetizationStore.clear_premium()
	MonetizationStore.set_ad_state(AdPolicy.fresh_state())
	quit()
