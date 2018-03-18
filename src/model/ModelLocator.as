/**
 Copyright (C) 2016  Johan Degraeve
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/gpl.txt>.
 
 */
package model
{
	import com.distriqt.extension.message.Message;
	import com.distriqt.extension.networkinfo.NetworkInfo;
	import com.freshplanet.ane.AirBackgroundFetch.BackgroundFetch;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	
	import mx.collections.ArrayCollection;
	import mx.resources.IResourceManager;
	import mx.resources.ResourceManager;
	
	import spark.collections.Sort;
	import spark.collections.SortField;
	import spark.components.Image;
	import spark.components.ViewNavigator;
	import spark.core.ContentCache;
	
	import databaseclasses.BgReading;
	import databaseclasses.Database;
	import databaseclasses.LocalSettings;
	import databaseclasses.Sensor;
	
	import distriqtkey.DistriqtKey;
	
	import events.DatabaseEvent;
	import events.NotificationServiceEvent;
	
	import services.AlarmService;
	import services.BackGroundFetchService;
	import services.BluetoothService;
	import services.CalibrationService;
	import services.DeepSleepService;
	import services.DexcomShareService;
	import services.DialogService;
	import services.HealthKitService;
	import services.NightScoutService;
	import services.NotificationService;
	import services.TextToSpeech;
	import services.TransmitterService;
	import services.UpdateService;
	
	import views.HomeView;
	import views.SettingsView;

	/**
	 * holds arraylist needed for displaying etc, like bgreadings of last 24 hours, loggings, .. 
	 */
	public class ModelLocator extends EventDispatcher
	{
		[ResourceBundle("general")]
		
		private static var _instance:ModelLocator = new ModelLocator();

		public static var image_calibrate_active:Image;
		public static var image_add:Image;
		public static var imageDone:Image;
		public static var imageBluetooth:Image;
		public static var imageBell:Image;
		public static var iconCache:ContentCache;

		public static const MAX_DAYS_TO_STORE_BGREADINGS_IN_MODELLOCATOR:int = 1;
		public static const DEBUG_MODE:Boolean = true;

		public static const IS_PRODUCTION:Boolean = false;
		
		public static function get instance():ModelLocator
		{
			return _instance;
		}

		private static var _resourceManagerInstance:IResourceManager;

		/**
		 * can be used anytime the resourcemanager is needed
		 */
		public static function get resourceManagerInstance():IResourceManager
		{
			return _resourceManagerInstance;
		}
		
		private static var _bgReadings:ArrayCollection;

		/**
		 * Sorted ascending, from small to large, ie latest element is also the last element
		 */
		public static function get bgReadings():ArrayCollection
		{
			return _bgReadings;
		}
		
		private static var _appStartTimestamp:Number;

		/**
		 * time that the application was started 
		 */
		public static function get appStartTimestamp():Number
		{
			return _appStartTimestamp;
		}
		
		public static var navigator:ViewNavigator;

		private static var _phoneMuted:Boolean;

		public static function get phoneMuted():Boolean
		{
			return _phoneMuted;
		}

		public static function set phoneMuted(value:Boolean):void
		{
			_phoneMuted = value;
		}

		
		public function ModelLocator()
		{
			if (_instance != null) {
				throw new Error("ModelLocator class can only be instantiated through ModelLocator.getInstance()");	
			}
			
			_appStartTimestamp = (new Date()).valueOf();
			
			_resourceManagerInstance = ResourceManager.getInstance();
			
			//bgreadings arraycollection
			_bgReadings = new ArrayCollection();
			_bgReadings.sort = BgReading.dataSortForBGReadings;
			Database.instance.addEventListener(DatabaseEvent.DATABASE_INIT_FINISHED_EVENT,getBgReadingsFromDatabase);
						
			function getBgReadingsFromDatabase():void {
				//this seems to be the best place to set ModelLocator.resourceManagerInstance.localeChain
				//which is set in TextToSpeech.init and which needs to be set after opening the database, because that's when the language setting is retrieved from the database
				TextToSpeech.init();
				
				Database.instance.addEventListener(DatabaseEvent.BGREADING_RETRIEVAL_EVENT, bgReadingReceivedFromDatabase);
				//bgreadings created after app start time are not needed because they are already stored in the _bgReadings by the transmitter service
				Database.getBgReadings((new Date()).valueOf() - 24 * 3600 * 1000, _appStartTimestamp);
			}

			function bgReadingReceivedFromDatabase(de:DatabaseEvent):void {
				if (de.data != null)
					if (de.data is BgReading) {
						if ((de.data as BgReading).timestamp > ((new Date()).valueOf() - MAX_DAYS_TO_STORE_BGREADINGS_IN_MODELLOCATOR * 24 * 60 * 60 * 1000)) {
							_bgReadings.addItem(de.data);
						}
					} else if (de.data is String) {
						if (de.data as String == Database.END_OF_RESULT) {
							_bgReadings.refresh();
							Database.getBlueToothDevice();
							Message.init(DistriqtKey.distriqtKey);
							TransmitterService.init();
							BackGroundFetchService.init();
							BluetoothService.init();
							
							NotificationService.instance.addEventListener(NotificationServiceEvent.NOTIFICATION_SERVICE_INITIATED_EVENT, HomeView.notificationServiceInitiated);
							NotificationService.init();
							
							CalibrationService.init();
							NetworkInfo.init(DistriqtKey.distriqtKey);
							
							//set AVAudioSession to AVAudioSessionCategoryPlayback with optoin AVAudioSessionCategoryOptionMixWithOthers
							//this ensures that texttospeech and playsound work also in background
							BackgroundFetch.setAvAudioSessionCategory(true);
							
							//to make sure the correct ANE is used
							BackgroundFetch.isVersion1_4_0();
							
							AlarmService.init();
							HealthKitService.init();
							
							DexcomShareService.init();
							NightScoutService.init();
							DeepSleepService.init();
							SettingsView.init();
							
							if (!IS_PRODUCTION) {
								UpdateService.init();
							}
							
							checkApplicationVersion();
						}
					}
			}

			iconCache = new ContentCache();
			iconCache.enableCaching = true;
			iconCache.enableQueueing = true;
			
			image_calibrate_active = new Image();
			image_calibrate_active.contentLoader = iconCache;
			image_calibrate_active.source = '../assets/image_calibrate_active.png';
			
			image_add = new Image();
			image_add.contentLoader = iconCache;
			image_add.source = "../assets/add48x48.png";
			
			imageDone = new Image();
			imageDone.contentLoader = iconCache;
			imageDone.source = "../assets/Done_48x48.png";
			
			imageBluetooth = new Image();
			imageBluetooth.contentLoader = iconCache;
			imageBluetooth.source = "../assets/bluetooth.png";
			
			imageBell = new Image();
			imageBell.contentLoader = iconCache;
			imageBell.source = "../assets/bell48.png";
		}
		
		private static function coreEvent(event:Event):void {
			var test:int = 0;
			test++;
		}
		
		/**
		 * add bgreading also removes bgreadings older than MAX_DAYS_TO_STORE_BGREADINGS_IN_MODELLOCATOR days but keep at least 5<br>
		 */
		public static function addBGReading(bgReading:BgReading, withRefresh:Boolean):void {
			_bgReadings.addItem(bgReading);
			if (withRefresh) {
				_bgReadings.refresh();
				
				if (_bgReadings.length <= 5)
					return;
				
				var firstBGReading:BgReading = _bgReadings.getItemAt(0) as BgReading;
				var now:Number = (new Date()).valueOf();
				while (now - firstBGReading.timestamp > MAX_DAYS_TO_STORE_BGREADINGS_IN_MODELLOCATOR * 24 * 3600 * 1000) {
					_bgReadings.removeItemAt(0);
					if (_bgReadings.length <= 5)
						break;
					firstBGReading = _bgReadings.getItemAt(0) as BgReading;
				}
			}
		}
		
		public static function refreshBgReadingArrayCollection():void {
			_bgReadings.refresh();
		}
		
		private static function checkApplicationVersion(event:Event = null):void {
			var newVersion:String = BackgroundFetch.getAppVersion();
			var currentVersion:String = LocalSettings.getLocalSetting(LocalSettings.LOCAL_SETTING_APPLICATION_VERSION);
			if (versionAIsSmallerThanB(currentVersion, newVersion)) {
				if (currentVersion != "0.0.0") {
					if (versionAIsSmallerThanB(currentVersion, '0.0.46')) {
						DialogService.openSimpleDialog(ModelLocator.resourceManagerInstance.getString('homeview',"info"),
							ModelLocator.resourceManagerInstance.getString('homeview',"info_additional_calibration_request_alert"));
					}
					if (versionAIsSmallerThanB(currentVersion, '0.0.53')) {
						DialogService.openSimpleDialog(ModelLocator.resourceManagerInstance.getString('homeview',"info"),
							ModelLocator.resourceManagerInstance.getString('homeview',"info_app_not_always_on_anymore"));
					}
				}
				LocalSettings.setLocalSetting(LocalSettings.LOCAL_SETTING_APPLICATION_VERSION, newVersion); 
			} else if (currentVersion == newVersion) {
				//version is equal nothing to do
			} else {
				//currentversion is greater than newversion, can happen if user did rollback to older version
				LocalSettings.setLocalSetting(LocalSettings.LOCAL_SETTING_APPLICATION_VERSION, newVersion);
			}
		}
		
		public static function versionAIsSmallerThanB(versionA:String, versionB:String):Boolean {
			var versionaSplitted:Array = versionA.split(".");
			var versionbSplitted:Array = versionB.split(".");
			if (new Number(versionaSplitted[0]) < new Number(versionbSplitted[0]))
				return true;
			if (new Number(versionaSplitted[0]) > new Number(versionbSplitted[0]))
				return false;
			if (new Number(versionaSplitted[1]) < new Number(versionbSplitted[1]))
				return true;
			if (new Number(versionaSplitted[1]) > new Number(versionbSplitted[1]))
				return false;
			if (new Number(versionaSplitted[2]) < new Number(versionbSplitted[2]))
				return true;
			if (new Number(versionaSplitted[2]) > new Number(versionbSplitted[2]))
				return false;
			return false;
		}
	}
}
