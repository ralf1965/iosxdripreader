package model
{
	import flash.utils.ByteArray;
	import flash.utils.Endian;
	
	import mx.collections.ArrayCollection;
	
	import Utilities.Crc;
	import Utilities.Trace;
	import Utilities.UniqueId;
	import Utilities.Libre.LibreAlarmReceiver;
	import Utilities.Libre.ReadingData;
	import Utilities.Libre.TransferObject;
	
	import databaseclasses.CommonSettings;
	
	public class Tomato
	{
		/**
		 * possible stattus miaomiao 
		 */
		private static const TOMATO_STATES_REQUEST_DATA_SENT:String = "REQUEST_DATA_SENT";
		/**
		 * possible stattus miaomiao 
		 */
		private static const TOMATO_STATES_RECIEVING_DATA:String = "RECIEVING_DATA";
		/**
		 * miaomiao status, one of  TOMATO_STATES_REQUEST_DATA_SENT or TOMATO_STATES_RECIEVING_DATA or empty string
		 */
		private static var s_state:String;
		private static var TOMATO_HEADER_LENGTH:int = 18;
		//other Tomato Variables
		private static var s_lastReceiveTimestamp:Number = 0;
		private static var s_full_data :ByteArray;
		private static var s_acumulatedSize:int = 0;
		private static var s_recviedEnoughData:Boolean;
		private static var expectedSize:int = 0;
		private static var packetNumber:int = 0;
		
		public function Tomato()
		{
		}
		
		public static function decodeTomatoPacket(buffer:ByteArray):ArrayCollection {
			var retArray:ArrayCollection = new ArrayCollection();
			// Check time, probably need to start on sending
			var now:Number = (new Date()).valueOf();
			if(now - s_lastReceiveTimestamp > 10*1000) {
				// We did not receive data in 10 seconds, moving to init state again
				myTrace("in decodeTomatoPacket, Recieved a buffer after " + (now - s_lastReceiveTimestamp) / 1000 +  " seconds, starting again. "+ "already acumulated " + s_acumulatedSize + " bytes.");
				s_state = TOMATO_STATES_REQUEST_DATA_SENT;
				packetNumber = 0;
			}
			
			s_lastReceiveTimestamp = now;
			if (buffer == null) {
				myTrace("in decodeTomatoPacket, null buffer passed to decodeTomatoPacket");
				return retArray;
			} 

			packetNumber++;
			myTrace("in decodeTomatoPacket, received packet number " + packetNumber);
			if (s_state == TOMATO_STATES_REQUEST_DATA_SENT) {
				if(buffer.length == 1 && getByteAt(buffer, 0) == int("0x32")) {
					myTrace("in decodeTomatoPacket, returning allow sensor confirm");
					
					var allowNewSensor:ByteArray = new ByteArray();
					
					allowNewSensor.writeByte(0xD3);
					allowNewSensor.writeByte(0x01);
					retArray.addItem(allowNewSensor);
					
					//command to start reading
					var ackMessage:ByteArray = new ByteArray();
					ackMessage.writeByte(0xF0);
					retArray.addItem(ackMessage);
					return retArray;
				}
				
				if(buffer.length == 1 && getByteAt(buffer, 0) == int("0x34")) {
					myTrace("in decodeTomatoPacket, No sensor has been found");
					return retArray;
				}
				
				// 18 is the expected header size
				if(buffer.length >= TOMATO_HEADER_LENGTH && getByteAt(buffer, 0) == int("0x28")) {
					// We are starting to receive data, need to start accumulating
					
					// &0xff is needed to convert to hex.
					expectedSize = 256 * (int)(getByteAt(buffer, 1)  & 0xFF) + (int)(getByteAt(buffer, 2) & 0xFF);
					myTrace("in decodeTomatoPacket, Starting to acumulate data expectedSize = " + expectedSize);
					InitBuffer();
					s_state = TOMATO_STATES_RECIEVING_DATA;

					//TO DO retry mechanism as in xdripplus
					try {
						addData(buffer);
					} catch (error:Error) {
						myTrace("in decodeTomatoPacket, CHECKSUM FAILED , TODO : BUILD IN RETRY MECHANISM");
					}
					return retArray;
				} else {
					myTrace("in decodeTomatoPacket, Unknown initial packet makeup received");
					return retArray;
				}
			}
			
			if (s_state == TOMATO_STATES_RECIEVING_DATA) {
				//myTrace("received more data s_acumulatedSize = " + s_acumulatedSize + ", current buffer size " + buffer.length);
				addData(buffer);
				return retArray;
			}
			myTrace("in decodeTomatoPacket, Very strange, In an unexpected state " + s_state);
			return retArray;
		}
		
		private static function InitBuffer():void {
			s_full_data = new ByteArray();
			s_acumulatedSize = 0;
			s_recviedEnoughData = false;
			
		}
		
		private static function addData(buffer:ByteArray):void {
			if(s_acumulatedSize + buffer.length > expectedSize) {
				myTrace("in addData, Error recieving too much data. exiting. s_acumulatedSize = " + s_acumulatedSize + 
					", buffer.length = " + buffer.length + ", expectedSize " + expectedSize);
				//??? send something to start back??
				return;
			}
			buffer.position = 0;
			buffer.readBytes(s_full_data, s_acumulatedSize, buffer.length);//System.arraycopy(buffer, 0, s_full_data, s_acumulatedSize, buffer.length);
			s_acumulatedSize += buffer.length;
			AreWeDone();
		}
		
		private static function AreWeDone():void {
			myTrace("in AreWeDone");
			if(s_recviedEnoughData) {
				// This reading already ended
				myTrace("in AreWeDone, s_recviedEnoughData = true");
				return;
			}
			
			if(s_acumulatedSize < 344 + TOMATO_HEADER_LENGTH + 1) {
				myTrace("in AreWeDone, we are not done");
				return;   
			}
			
			var data:ByteArray = new ByteArray();
			data.endian = Endian.LITTLE_ENDIAN;
			myTrace("in AreWeDone, s_full_data =  " + Utilities.UniqueId.bytesToHex(s_full_data));
			s_full_data.position = TOMATO_HEADER_LENGTH;
			s_full_data.readBytes(data, 0, 344);
			s_recviedEnoughData = true;
			var checksum_ok:Boolean = Crc.LibreCrc(data);
			myTrace("in AreWeDone, We have all the data that we need, s_acumulatedSize = " + s_acumulatedSize + ". checksum_ok = " + checksum_ok + ". Data = " + Utilities.UniqueId.bytesToHex(data));
			
			if (!checksum_ok) {
				myTrace("in AreWeDone, CHECKSUM NOT OK");
				throw new Error("CHECKSUM_FAILED"); 
				return;
			}
			
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_MIAOMIAO_BATTERY_LEVEL, (new Number(getByteAt(s_full_data,13))).toString());
			
			//hardware HexDump.toHexString(s_full_data,14,2))
			s_full_data.position = 14;
			var temp:ByteArray = new ByteArray();s_full_data.readBytes(temp, 0,2);
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_MIAOMIAO_HARDWARE, Utilities.UniqueId.bytesToHex(temp));
			
			//firmware HexDump.toHexString(s_full_data,16,2)
			s_full_data.position = 16;
			temp = new ByteArray();s_full_data.readBytes(temp, 0, 2);
			CommonSettings.setCommonSetting(CommonSettings.COMMON_SETTING_MIAOMIAO_FW,Utilities.UniqueId.bytesToHex(temp));
			myTrace("in AreWeDone, COMMON_SETTING_MIAOMIAO_HARDWARE = " + CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_MIAOMIAO_HARDWARE) + ", COMMON_SETTING_MIAOMIAO_FW = " + CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_MIAOMIAO_FW) + ", battery level  " + CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_MIAOMIAO_BATTERY_LEVEL)); 
			
			var mResult:ReadingData = LibreAlarmReceiver.parseData(0, "tomato", data);
			LibreAlarmReceiver.CalculateFromDataTransferObject(new TransferObject(1, mResult), true);
		}
		
		
		private static function myTrace(log:String):void {
			Trace.myTrace("Tomato.as", log);
		}
		
		private static function getByteAt(buffer:ByteArray, position:int):int {
			buffer.position = position;
			return buffer.readByte();
		}
	}
}