package;

using api.IdeckiaApi;

typedef Props = {
	@:shared
	@:editable('Obs address', "localhost:4455")
	var address:String;
	@:shared
	@:editable('Obs password')
	var password:String;
}

typedef ObsSceneObject = {
	var sceneIndex:UInt;
	var sceneName:String;
}

typedef ObsSceneItemObject = {
	var sceneItemEnabled:Bool;
	var sceneItemId:UInt;
	var sourceName:String;
}

typedef ObsScenesResponse = {
	var currentProgramSceneName:String;
	var currentPreviewSceneName:String;
	var scenes:Array<ObsSceneObject>;
}

typedef ObsSceneItemsResponse = {
	var sceneItems:Array<ObsSceneItemObject>;
}

@:name("obs-scenes")
@:description("Create a directory with the current obs scenes dynamically")
class ObsScenes extends IdeckiaAction {
	static var SCENE_BG = Macros.getImageData('film_frame.png');
	static var obs:ObsWebsocketJs;

	override public function init(initialState:ItemState):js.lib.Promise<ItemState> {
		return new js.lib.Promise((resolve, reject) -> {
			getImageData('film_frame.png');
			checkConnection().then(_ -> {
				resolve(initialState);
			}).catchError(e -> server.log.error('Error connecting to OBS: $e'));
		});
	}

	function checkConnection() {
		return new js.lib.Promise((resolve, reject) -> {
			if (obs != null) {
				server.log.debug('OBS already connected.');
				resolve(true);
				return;
			}

			obs = new ObsWebsocketJs();
			var websocketProtocol = 'ws://';
			var address = StringTools.startsWith(props.address, websocketProtocol) ? props.address : websocketProtocol + props.address;
			server.log.info('Connecting to obs-websocket [address=${address}].');
			obs.connect(address, props.password).then((_) -> {
				server.log.info("Success! We're connected & authenticated.");
				resolve(true);
			}).catchError(error -> {
				obs = null;
				var msg = if (Std.string(error).indexOf('ECONNREFUSED') != -1) {
					"Can't connect to OBS Studio. Be sure it is running and the Websocket server is enabled (Tools > Websocket Server Settings)";
				} else {
					'Error connecting to OBS: $error';
				}
				reject(msg);
			});
		});
	}

	public function execute(currentState:ItemState):js.lib.Promise<ActionOutcome> {
		server.log.error('click:');
		return new js.lib.Promise((resolve, reject) -> {
			checkConnection().then(_ -> {
				getScenes().then(resolve).catchError(reject);
			}).catchError(e -> server.dialog.error('OBS Scenes', e));
		});
	}

	function getScenes() {
		return new js.lib.Promise((resolve, reject) -> {
			var scenes:Array<DynamicDirItem> = [];
			obs.call('GetSceneList', {}).then(response -> {
				var obsResp:ObsScenesResponse = cast response;
				for (s in obsResp.scenes) {
					server.log.debug(s);
					scenes.push({
						text: s.sceneName,
						icon: SCENE_BG,
						bgColor: 'ffdddddd',
						textColor: 'ff333333',
						textSize: 20,
						textPosition: 'center',
						actions: [
							{
								name: 'obs-control',
								props: {
									address: props.address,
									password: props.password,
									request_type: 'Switch scene',
									scene_name: s.sceneName,
									clickCallback: getItems.bind(s.sceneName)
								}
							}
						]
					});
				}

				var rows = 2;
				var columns = 2;
				while (rows * columns < scenes.length) {
					rows++;
					if (rows * columns >= scenes.length)
						break;
					columns++;
				}
				resolve(new ActionOutcome({
					directory: {
						rows: rows,
						columns: columns,
						items: scenes
					}
				}));
			}).catchError(reject);
		});
	}

	function getItems(sceneName:String) {
		return new js.lib.Promise((resolve, reject) -> {
			var sceneItems:Array<DynamicDirItem> = [];
			obs.call('GetSceneItemList', {sceneName: sceneName}).then(response -> {
				var obsResp:ObsSceneItemsResponse = cast response;
				for (s in obsResp.sceneItems) {
					server.log.debug(s);
					sceneItems.push({
						text: s.sourceName,
						bgColor: s.sceneItemEnabled ? 'ff00aa00' : 'ffaa0000',
						actions: [
							{
								name: 'obs-control',
								props: {
									address: props.address,
									password: props.password,
									request_type: 'Toggle source',
									scene_name: sceneName,
									source_name: s.sourceName
								}
							}
						]
					});
				}

				var rows = 2;
				var columns = 2;
				while (rows * columns < sceneItems.length) {
					rows++;
					if (rows * columns >= sceneItems.length)
						break;
					columns++;
				}
				resolve(new ActionOutcome({
					directory: {
						rows: rows,
						columns: columns,
						items: sceneItems
					}
				}));
			}).catchError(reject);
		});
	}

	public static function getImageData(name:String) {
		var filePath:String = haxe.io.Path.join([js.Node.__dirname, name]);

		if (sys.FileSystem.exists(filePath))
			SCENE_BG = haxe.crypto.Base64.encode(sys.io.File.getBytes(filePath));
	}
}
