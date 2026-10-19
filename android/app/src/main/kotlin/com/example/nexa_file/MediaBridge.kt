package com.example.nexa_file
import android.content.Context
import android.media.MediaPlayer
import android.net.Uri
import android.view.View
import android.widget.MediaController
import android.widget.VideoView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MediaBridge(private val context:Context,messenger:BinaryMessenger){private var player:MediaPlayer?=null;init{MethodChannel(messenger,"nexa_file/audio").setMethodCallHandler(::handle)}private fun handle(call:MethodCall,result:MethodChannel.Result){try{when(call.method){"load"->{player?.release();player=MediaPlayer.create(context,Uri.parse(call.argument<String>("uri")!!));result.success(mapOf("duration" to (player?.duration?:0)))};"play"->{player?.start();result.success(null)};"pause"->{player?.pause();result.success(null)};"seek"->{player?.seekTo(call.argument<Int>("position")?:0);result.success(null)};"state"->result.success(mapOf("position" to (player?.currentPosition?:0),"duration" to (player?.duration?:0),"playing" to (player?.isPlaying?:false)));"dispose"->{player?.release();player=null;result.success(null)};else->result.notImplemented()}}catch(e:Exception){result.error("MEDIA",e.message,e.javaClass.name)}}}
class VideoViewFactory(private val context:Context):PlatformViewFactory(StandardMessageCodec.INSTANCE){override fun create(context:Context,id:Int,args:Any?):PlatformView=NativeVideoView(context,(args as Map<*,*>)["uri"] as String)}
private class NativeVideoView(context:Context,uri:String):PlatformView{private val view=VideoView(context).apply{setVideoURI(Uri.parse(uri));setMediaController(MediaController(context).also{it.setAnchorView(this)});setOnPreparedListener{start()}};override fun getView():View=view;override fun dispose(){view.stopPlayback()}}
