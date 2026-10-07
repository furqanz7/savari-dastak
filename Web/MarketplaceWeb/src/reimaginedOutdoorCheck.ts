import { createGroceryScene } from "./reimaginedGroceryScene";
import type { OutdoorWeather } from "./reimaginedWeather";

// Isolated local visual regression fixture; no geolocation, requests or live data.
if(import.meta.env.DEV){
  const canvas=document.querySelector<HTMLCanvasElement>("canvas")!;
  const scene=createGroceryScene(canvas,{counter:false,outside:true,onStatus:()=>{}});
  const apply=(kind:string)=>{
    const now=Date.now(),night=kind.startsWith("night"),rain=kind.includes("rain"),snow=kind.includes("snow");
    const weather:OutdoorWeather={observedAt:now,fetchedAt:now,temperature:snow?-2:24,cloud:rain||snow?.85:.2,precipitation:rain?2:snow?1:0,code:rain?61:snow?73:1,wind:kind==="calm"?0:rain?35:18,gust:kind==="calm"?0:rain?55:28,direction:240,isDay:!night,sunrise:[now-(night?18:6)*3600000],sunset:[now+(night?-6:6)*3600000],timezone:"UTC"};
    scene.setWeather(weather);canvas.dataset.testWeather=kind;
    document.querySelector("#status")!.textContent=`Local simulated ${kind} — not live weather`;
  };
  document.querySelectorAll<HTMLButtonElement>("[data-weather]").forEach(button=>button.addEventListener("click",()=>apply(button.dataset.weather!)));
  apply("breeze");
  import.meta.hot?.dispose(()=>scene.dispose());
}else document.body.textContent="Local motion check disabled.";
