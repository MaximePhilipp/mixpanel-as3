package com.mixpanel
{
	import com.mixpanel.Mixpanel;
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.TimerEvent;
	import flash.net.SharedObject;
	import flash.utils.Timer;
	
	import mx.utils.UIDUtil;
	
	import org.flexunit.Assert;
	import org.flexunit.async.Async;
	
	public class MixpanelTest
	{
		private var mixpanel:Mixpanel;
		private var localMix:Mixpanel;
		private var asyncDispatcher:EventDispatcher;
		private static var asyncIDCounter:int = 0;
		
		private function makeMP(token:String=null, config:Object=null):Mixpanel {
			if (!token) { token = UIDUtil.createUID(); }
			var mp:Mixpanel = new Mixpanel(token);
			if (config) { mp.set_config(config); }
			return mp;
		}
		
		[Before]
		public function setUp():void
		{
			mixpanel = makeMP("4874fb5a6ac20d3c883349defcfb9c99", { test: 1 });
			localMix = makeMP();
			
			asyncDispatcher = new EventDispatcher();
		}
		
		[After]
		public function tearDown():void
		{
		}
		
		private function asyncHandler(callback:Function, timeout:int = 10000):int {
			var _this:MixpanelTest = this;
			var handler:Function = Async.asyncHandler(this, function(evt:AsyncEvent, ...ignore):void {
				callback.apply(_this, evt.args); 				
			}, timeout, {}, function():void {
				Assert.fail("async test failed to return within timeout");
			});
			
			var id:int = asyncIDCounter++;
			asyncDispatcher.addEventListener(id.toString(), handler);
			
			return id;
		}
		
		private function start(id:int, ...args):void {
			asyncDispatcher.dispatchEvent(new AsyncEvent(id.toString(), args));
		}
		
		[Test(async, description="check track callback")]
		public function track():void {
			var asyncID:int = asyncHandler(function(resp:String):void {
				Assert.assertEquals("server returned success", resp, "1");
			});
			
			mixpanel.track("test_track", {"hello": "world"}, function(resp:String):void {	
				start(asyncID, resp);
			});
		}
		
		[Test(async, description="check parallel track()'s")]
		public function track_multiple():void {
			var result:Array = [];
			
			mixpanel.track("test_multiple", function(resp:String):void { 
				result.push(1);
			});
			mixpanel.track("test_multiple", function(resp:String):void {
				result.push(2);
			});
			
			Async.delayCall(this, function():void {
				Assert.assertTrue("Both track()'s failed to fire", result.indexOf(1) != -1 && result.indexOf(2) != -1);
			}, 2000);
		}
		
		[Test(description="sets distinct_id if user doesn't have one")]
		public function sets_distinct_id():void {
			var data:Object,
				id:String = UIDUtil.createUID();
			
			data = localMix.track("test_distinct_id");
			Assert.assertTrue("track() should set distinct id if it doesn't exist", data.properties.hasOwnProperty('distinct_id'));
			
			localMix.identify(id);
			data = localMix.track("test_distinct_id");
			Assert.assertEquals("track() should not override an already set distinct id", data.properties["distinct_id"], id);
		}
		
		[Test(async, description="disable() disabled all tracking from firing")]
		public function disable_events_from_firing():void {
			localMix.disable();
			
			localMix.track("e_a", function(resp:String):void {
				Assert.assertEquals("track should return an error", resp, 0);
			});
			
			var mp:Mixpanel = makeMP();
			mp.disable(["event_a"]);
			mp.disable(["event_c"]);
			
			var asyncID:int = asyncHandler(function(resp:String):void {
				Assert.assertEquals("server returned success", resp, "1");
			});
			
			mp.track("event_a", function(resp:String):void {
				Assert.assertEquals("track should return an error", resp, 0);
			});
			mp.track("event_b", function(resp:String):void {
				start(asyncID, resp);
			});
			mp.track("event_c", function(resp:String):void {
				Assert.assertEquals("track should return an error", resp, 0);
			});
		}
		
		[Test(description="storage should upgrade")]
		public function storage_upgrade():void {
			var old:SharedObject = SharedObject.getLocal("mixpanel"),
				token:String = UIDUtil.createUID();
			
			old.data[token] = {"all": { "prop_1": "test" }, "events": { "prop_2": "test" }, "funnels": { "prop_3": "test" }};
			
			var mp:Mixpanel = makeMP(token);

			Assert.assertTrue("old data[all] was imported", mp.storage.has("prop_1"));
			Assert.assertTrue("old data[events] was imported", mp.storage.has("prop_2"));
			Assert.assertFalse("old data[funnels] was not imported", mp.storage.has("prop_3"));
			Assert.assertFalse("old data was deleted", old.data.hasOwnProperty(token));
		}
		
		[Test(description="mixpanel instances should load data from shared objects")]
		public function load_save_data():void {
			var token:String = UIDUtil.createUID(),
				mp:Mixpanel = makeMP(token),
				prop:String = UIDUtil.createUID();
			
			mp.register({ "test": prop });
			
			var mp2:Mixpanel = makeMP(token);
			Assert.assertEquals("library should load existing shared object", mp2.storage.get("test"), prop);
			
			var mp3:Mixpanel = makeMP();
			Assert.assertFalse("library should create new shared object", mp3.storage.has("test"));
		}
		
		[Test(description="track() super properties are included")]
		public function track_super_properties():void {
			var props:Object = { 'a': 'b', 'c': 'd' };
			localMix.register(props);
			
			var data:Object = localMix.track('test'),
				dp:Object = data.properties;
			
			Assert.assertTrue("token included in properties", dp.hasOwnProperty("token"));
			Assert.assertTrue("time included in properties", dp.hasOwnProperty("time"));
			Assert.assertTrue("mp_lib included in properties", dp.hasOwnProperty("mp_lib"));
			Assert.assertEquals("super properties included properly", dp['a'], props['a']);
			Assert.assertEquals("super properties included properly", dp['c'], props['c']);
		}
		
		[Test(description="track() manual props override super props")]
		public function track_manual_override():void {
			var props:Object = { 'a': 'b', 'c': 'd' };
			localMix.register(props);
			
			var data:Object = localMix.track('test', { "a": "test" }),
				dp:Object = data.properties;
			
			Assert.assertEquals("manual property overrides successfully", dp["a"], "test");
			Assert.assertEquals("other superproperties unnaffected", dp["c"], "d");
		}
		
		[Test(description="set_config works")]
		public function set_config():void {
			Assert.assertEquals("config.test is false", localMix.config.test, false);
			localMix.set_config({ test: true });
			Assert.assertEquals("config.test is true", localMix.config.test, true);
		}
		
		[Test(description="register()")]
		public function register():void {
			var props:Object = {'hi': 'there'};
			
			Assert.assertFalse("empty before setting", localMix.storage.has("hi"));
			
			localMix.register(props);
			
			Assert.assertTrue("prop set properly", localMix.storage.has("hi"));
		}
		
		[Test(description="register_once()")]
		public function register_once():void {
			var props:Object = {'hi': 'there'},
				props1:Object = {'hi': 'ho'};
			
			Assert.assertFalse("empty before setting", localMix.storage.has("hi"));
			
			localMix.register_once(props);
			
			Assert.assertTrue("prop set properly", localMix.storage.has("hi"));
			
			localMix.register_once(props1);
			
			Assert.assertEquals("doesn't override", localMix.storage.get("hi"), props["hi"]);
		}
		
		[Test(description="unregister()")]
		public function unregister():void {
			var props:Object = {'hi': 'there'};
			
			Assert.assertFalse("empty before setting", localMix.storage.has("hi"));
			
			localMix.register(props);
			
			Assert.assertTrue("prop set properly", localMix.storage.has("hi"));
			
			localMix.unregister("hi");
			
			Assert.assertFalse("empty after unregistering", localMix.storage.has("hi"));
		}
		
		[Test(description="identify")]
		public function identify():void {
			var distinct:String = UIDUtil.createUID(),
				changed:String = UIDUtil.createUID();
			
			Assert.assertFalse("empty before setting", localMix.storage.has("distinct_id"));
			
			localMix.identify(distinct);
			Assert.assertEquals("set distinct", localMix.storage.get("distinct_id"), distinct);
			
			localMix.identify(changed);
			Assert.assertEquals("distinct was changed", localMix.storage.get("distinct_id"), changed);
		}
		
		[Test(description="name_tag")]
		public function name_tag():void {
			var name:String = "bob";
			
			Assert.assertFalse("empty before setting", localMix.storage.has("mp_name_tag"));
			
			localMix.name_tag(name);
			Assert.assertEquals("name tag set", localMix.storage.get("mp_name_tag"), name);
		}

	}
}










