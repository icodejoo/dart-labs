#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mpv/client.h>
#include <mpv/render.h>
/* 软渲染 render API 冒烟：vo=libmpv + sw 后端，统计渲染帧数 */
int main(int c,char**v){
 mpv_handle*h=mpv_create(); if(!h){puts("create fail");return 1;}
 mpv_set_option_string(h,"vo","libmpv"); mpv_set_option_string(h,"ao","null");
 if(mpv_initialize(h)<0){puts("init fail");return 1;}
 mpv_render_param ps[]={{MPV_RENDER_PARAM_API_TYPE,(void*)MPV_RENDER_API_TYPE_SW},{0,0}};
 mpv_render_context*rc=NULL; int r=mpv_render_context_create(&rc,h,ps); printf("render_ctx=%d\n",r);
 if(r<0) return 2;
 const char*cmd[]={"loadfile",v[1],NULL}; mpv_command(h,cmd);
 int w=320,hh=240; unsigned char*buf=malloc(w*hh*4); int frames=0,end=0;
 for(int i=0;i<300&&!end;i++){ mpv_event*e=mpv_wait_event(h,0.1);
  if(e->event_id==MPV_EVENT_END_FILE) end=1;
  if(mpv_render_context_update(rc)&MPV_RENDER_UPDATE_FRAME){
   int sz[2]={w,hh}; size_t stride=w*4;
   mpv_render_param rp[]={{MPV_RENDER_PARAM_SW_SIZE,sz},{MPV_RENDER_PARAM_SW_FORMAT,"rgb0"},{MPV_RENDER_PARAM_SW_STRIDE,&stride},{MPV_RENDER_PARAM_SW_POINTER,buf},{0,0}};
   if(mpv_render_context_render(rc,rp)>=0) frames++; }
 }
 printf("sw frames=%d end=%d\n",frames,end);
 mpv_render_context_free(rc); mpv_terminate_destroy(h); return 0;}
