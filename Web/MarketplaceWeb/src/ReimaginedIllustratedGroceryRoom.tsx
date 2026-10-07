import { memo, useId } from "react";
import "./design/reimaginedIllustratedGroceryRoom.css";

// Decorative architecture only. These unbranded package shapes are not catalogue
// products, stock indicators, navigation targets or a second taxonomy.
const palette = ["#cba56b", "#879b78", "#c87757", "#d3c8a2", "#688984", "#bca178"];
const lanes = [0, 1, 2, 3];
const positions = Array.from({ length: 17 }, (_, index) => index);

function StockedRack({ side, prefix }: { side: "left" | "right"; prefix: string }) {
  const mirror = side === "right";
  return <g transform={mirror ? "translate(1800 0) scale(-1 1)" : undefined}>
    <path d="M-100 200 670 379 670 708 -100 1010Z" fill={`url(#${prefix}-rack)`} />
    <path d="M-100 200 670 379 702 367 -70 180Z" fill="#d3b891" />
    <path d="M670 379 702 367 702 696 670 708Z" fill="#998269" />
    {lanes.map(row => {
      const nearY = 376 + row * 170;
      const farY = 458 + row * 71;
      return <g key={row}>
        <path d={`M-100 ${nearY - 120} 670 ${farY - 50} 670 ${farY} -100 ${nearY}Z`} fill="#344539" opacity=".18" />
        {positions.map(index => {
          const t = index / 17;
          const scale = 1.55 - t * .9;
          const x = -65 + t * 718;
          const y = nearY + (farY - nearY) * t - 12;
          return <g key={index} transform={`translate(${x} ${y}) scale(${scale})`} color={palette[(index + row * 2 + (mirror ? 1 : 0)) % palette.length]}>
            <ellipse cx="13" cy="1" rx="20" ry="4" fill="#283528" opacity=".22" />
            <use href={`#${prefix}-${(index + row) % 3 === 0 ? "bottle" : (index + row) % 3 === 1 ? "pouch" : "tin"}`} />
          </g>;
        })}
        <path d={`M-100 ${nearY} 670 ${farY} 670 ${farY + 9} -100 ${nearY + 24}Z`} fill="#b18b62" />
        <path d={`M-100 ${nearY} 670 ${farY}`} stroke="#efd7ac" strokeWidth="3" />
        <path d={`M-100 ${nearY + 24} 670 ${farY + 9}`} stroke="#645c47" strokeWidth="3" opacity=".35" />
        {[0, 1, 2, 3, 4].map(index => {
          const t = (index + .5) / 5;
          const x = -100 + t * 770;
          const y = nearY + (farY - nearY) * t + 4;
          return <path key={index} d={`M${x} ${y} l${36 - t * 22} ${3 - t * 2} v${9 - t * 5} l-${36 - t * 22} -${3 - t * 2}Z`} fill="#eee5cc" opacity=".9" />;
        })}
      </g>;
    })}
    <path d="M-94 203V1010M658 377V710" stroke="#bd9f79" strokeWidth="14" />
    <path d="M-86 204V1009M663 381V708" stroke="#e3caa2" strokeWidth="3" opacity=".65" />
  </g>;
}

function Checkout({ prefix, compact }: { prefix: string; compact: boolean }) {
  return <g className="grocery-room-checkout" transform={compact ? "translate(-340 240)" : undefined}>
    <ellipse cx="1500" cy="1010" rx="330" ry="60" fill="#57654c" opacity=".17" />
    <path d="M1390 414V514M1607 414V514" stroke="#645d4a" strokeWidth="3" />
    <rect x="1340" y="487" width="310" height="80" rx="8" fill="#345044" />
    <rect x="1347" y="494" width="296" height="66" rx="4" fill="none" stroke="#d9c8a1" opacity=".5" />
    <text x="1380" y="538" fill="#f2e8ce" fontSize="24" letterSpacing="4">BILLING</text>
    <path d="m1584 523 15 10 -15 10m-20-10h34" fill="none" stroke="#e4c391" strokeWidth="3" />
    <g className="grocery-room-staff">
      <path d="M1452 772q-18-100 12-129l39-17 40 19q32 40 25 127Z" fill="#e4d9c1" />
      <path d="m1480 641 8 24 27 1 9-25 12 9-6 41 12 86h-79l12-86-9-44Z" fill="#3d6552" />
      <path d="m1490 670 16 9 13-9" fill="none" stroke="#acb79b" strokeWidth="2" />
      <rect x="1488" y="715" width="29" height="29" rx="3" fill="#345644" stroke="#86a187" />
      <path d="M1486 628v22q19 19 35-1v-22" fill="#bd8e70" />
      <ellipse cx="1504" cy="604" rx="30" ry="39" fill="#c59c7b" />
      <path d="M1475 609q-13-50 29-48 35-1 31 43l-9-17q-23 7-40-4Z" fill="#3b3930" />
      <path d="M1487 609h5m17 0h5" stroke="#514439" strokeWidth="2" strokeLinecap="round" />
      <path d="M1496 626q9 5 16-1" fill="none" stroke="#966e53" strokeWidth="2" strokeLinecap="round" />
      <path d="M1455 680q-17 35-11 63l50 18 5-13-31-23 11-34M1547 682q16 42 12 59l-29 22-8-12 20-22-13-37" fill="#e4d9c1" />
      <path d="m1490 746 18 5-1 13-20-5m38-10-18 7 4 10 20-6" fill="#c59c7b" />
    </g>
    <path d="M1190 787 1545 738 1820 824 1431 898Z" fill="#484b3c" />
    <path d="M1190 787 1431 898 1431 1115 1190 968Z" fill={`url(#${prefix}-counterSide)`} />
    <path d="M1431 898 1820 824V1036L1431 1115Z" fill={`url(#${prefix}-counter)`} />
    <path d="M1190 787 1431 898 1820 824v18l-389 78-241-114Z" fill="#a88c67" />
    <path d="m1195 787 235 104 384-69" fill="none" stroke="#dad0ae" strokeWidth="3" />
    {[0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map(index => <path key={index} d={`M${1450 + index * 38} ${916 - index * 7.5}v188`} stroke="#213c32" strokeWidth="3" opacity=".18" />)}
    <text x="1490" y="999" fill="#e2d7b6" fontSize="35" fontWeight="600" letterSpacing="-1" transform="rotate(-11 1490 999)">Dastak<tspan fill="#c6a26a">.</tspan></text>
    <g transform="translate(1340 705)">
      <path d="m18 46 62 11-8 14-69-9Z" fill="#44493d" />
      <path d="M34 20v30l27 5V24" fill="#5c6356" />
      <path d="M0-12 81-2 73 39-7 27Z" fill="#3c493f" stroke="#b5b7a1" strokeWidth="5" />
      <path d="m4-6 70 8-5 29-70-10Z" fill="#708b78" />
      <path d="m15 3 23 3m-25 6 46 5" stroke="#cdd9bf" strokeWidth="3" />
    </g>
    <g transform="translate(1655 748)">
      <path d="m0 0 72 18-14 42-57-17Z" fill="#b28d58" />
      <path d="m19 4 6-32 27 6 2 33" fill="none" stroke="#c4a46e" strokeWidth="4" />
      <path d="m10 19 42 10" stroke="#ddc79e" strokeWidth="2" />
    </g>
  </g>;
}

const GroceryDrawing = memo(function GroceryDrawing({ compact = false }: { compact?: boolean }) {
  const prefix = `grocery-${useId().replaceAll(":", "")}`;
  return <svg className={`grocery-room-art ${compact ? "grocery-room-art-compact" : "grocery-room-art-wide"}`} viewBox={compact ? "420 -100 1160 1640" : "0 0 1800 1100"} preserveAspectRatio={compact ? "xMidYMid slice" : "xMaxYMid slice"} aria-hidden="true" focusable="false">
    <defs>
      <linearGradient id={`${prefix}-wall`} x2="0" y2="1"><stop stopColor="#e3dec7" /><stop offset="1" stopColor="#c7c9ae" /></linearGradient>
      <linearGradient id={`${prefix}-floor`} x2="0" y2="1"><stop stopColor="#d5d1b9" /><stop offset="1" stopColor="#ede4ce" /></linearGradient>
      <linearGradient id={`${prefix}-rack`}><stop stopColor="#7f7155" /><stop offset=".7" stopColor="#b5a586" /><stop offset="1" stopColor="#c4b598" /></linearGradient>
      <linearGradient id={`${prefix}-counter`}><stop stopColor="#5a7660" /><stop offset="1" stopColor="#84967a" /></linearGradient>
      <linearGradient id={`${prefix}-counterSide`}><stop stopColor="#365343" /><stop offset="1" stopColor="#5c765b" /></linearGradient>
      <radialGradient id={`${prefix}-light`}><stop stopColor="#fff9df" stopOpacity=".8" /><stop offset="1" stopColor="#fff5d5" stopOpacity="0" /></radialGradient>
      <radialGradient id={`${prefix}-edge`}><stop offset=".4" stopColor="#234132" stopOpacity="0" /><stop offset="1" stopColor="#234132" stopOpacity=".16" /></radialGradient>
      <pattern id={`${prefix}-grain`} width="19" height="9" patternUnits="userSpaceOnUse"><path d="M0 2h12m2 4h9" stroke="#e0c9a2" strokeWidth=".6" opacity=".2" /></pattern>
      <g id={`${prefix}-pouch`}>
        <path d="M-2-65h32l-3 12 3 50q-15 4-32 0l3-50Z" fill="currentColor" />
        <path d="M0-62h28M0-7h28" stroke="#f0e6ce" strokeWidth="2" opacity=".5" />
        <rect x="4" y="-46" width="22" height="27" rx="2" fill="#efe5c7" opacity=".8" />
        <path d="m10-28 6-10 5 10" stroke="#65765a" strokeWidth="2" fill="none" /><path d="M8-23h15" stroke="#ac9c7c" />
        <path d="M-1-57v44" stroke="#fff8dc" opacity=".24" strokeWidth="3" />
      </g>
      <g id={`${prefix}-bottle`}>
        <rect x="6" y="-76" width="17" height="9" rx="2" fill="#d8d2b8" />
        <path d="M7-67v12L1-43v40q13 5 27 0v-40l-6-12v-12Z" fill="currentColor" />
        <rect x="3" y="-37" width="23" height="24" rx="2" fill="#eee6ce" opacity=".8" />
        <ellipse cx="15" cy="-26" rx="7" ry="6" fill="#6e855f" opacity=".8" />
        <path d="M5-46v35" stroke="#fff" opacity=".28" strokeWidth="3" />
      </g>
      <g id={`${prefix}-tin`}>
        <rect x="0" y="-49" width="31" height="48" rx="4" fill="currentColor" />
        <ellipse cx="15.5" cy="-49" rx="15.5" ry="4" fill="#d8d3bd" />
        <rect x="1" y="-36" width="29" height="22" fill="#eee5cd" opacity=".8" />
        <path d="M8-25h15m-12 5h9" stroke="#889376" strokeWidth="2" />
        <path d="M4-42v32" stroke="#fff" opacity=".25" strokeWidth="2" />
      </g>
    </defs>
    {/* Architecture shares one vanishing point; no photographs or external fetches. */}
    <rect x="-700" y="-300" width="3200" height="2100" fill={`url(#${prefix}-wall)`} />
    <path d="M-300-100 2100-100 1185 350 650 350Z" fill="#f1ebd7" />
    <path d="M-100 0 650 350 650 738-100 1120Z" fill="#c9ceb6" />
    <path d="M1900 0 1185 350 1185 738 1900 1120Z" fill="#c0c7ab" />
    <path d="M-200 1100 650 695 1185 695 2000 1100v600H-200Z" fill={`url(#${prefix}-floor)`} />
    {[-700, -250, 180, 600, 1000, 1400, 1830, 2270].map(x => <path key={x} d={`M916 510 ${x} 1700`} stroke="#b1b8a1" strokeWidth="2" opacity=".38" />)}
    {[746, 815, 930, 1110, 1370, 1670].map(y => <path key={y} d={`M-200 ${y}H2000`} stroke="#b5bba4" strokeWidth="2" opacity=".33" />)}
    <path d="M650 350H1185V738H650Z" fill="#dedbc0" />
    <path d="M655 540H1180v190H655Z" fill="#a1b098" />
    <path d="M680 350v385m100-385v385m405-385v385" stroke="#b5b99e" strokeWidth="3" />
    <text x="916" y="435" textAnchor="middle" fontSize="57" fontWeight="650" letterSpacing="-3" fill="#365442">Dastak<tspan fill="#ba9559">.</tspan></text>
    <text x="916" y="467" textAnchor="middle" fontSize="9" letterSpacing="3.2" fill="#65755d">YOUR NEIGHBOURHOOD, THROUGH ONE DOOR</text>
    <g opacity=".9">
      <path d="M788 527H1060V710H788Z" fill="#54725c" stroke="#e7dfc2" strokeWidth="8" />
      {[0, 1, 2].map(row => <g key={row}>
        {[0, 1, 2, 3, 4, 5, 6, 7].map(index => <g key={index} transform={`translate(${800 + index * 31} ${578 + row * 55}) scale(.5)`} color={palette[(index + row) % 6]}><use href={`#${prefix}-tin`} /></g>)}
        <path d={`M790 ${583 + row * 55}h270`} stroke="#e1ceaa" strokeWidth="7" />
      </g>)}
    </g>
    {[-300, 230, 670, 1185, 1590, 2100].map(x => <path key={x} d={`M${x}-150 916 350`} stroke="#c7ccb3" strokeWidth="3" />)}
    {[0, 1, 2].map(index => <g key={index} transform={`translate(${index * 225} ${index * 122}) scale(${1 - index * .24})`}>
      <path d="M355-10v116m1080-116v116" stroke="#767d67" strokeWidth="3" />
      <ellipse cx="355" cy="164" rx="115" ry="72" fill={`url(#${prefix}-light)`} />
      <ellipse cx="1435" cy="164" rx="115" ry="72" fill={`url(#${prefix}-light)`} />
      <path d="m299 105 12 28h89l12-28Z" fill="#41614c" /><ellipse cx="355" cy="133" rx="44" ry="7" fill="#fff3cd" />
      <path d="m1379 105 12 28h89l12-28Z" fill="#41614c" /><ellipse cx="1435" cy="133" rx="44" ry="7" fill="#fff3cd" />
    </g>)}
    <ellipse cx="630" cy="950" rx="260" ry="43" fill="#647359" opacity=".16" />
    <StockedRack side="left" prefix={prefix} /><StockedRack side="right" prefix={prefix} />
    <path d="M-100 202 670 379v28L-100 248Z" fill="#345442" />
    <text x="80" y="275" fontSize="23" letterSpacing="2" fill="#eee3c4" transform="rotate(12 80 275)">GROCERY &amp; KITCHEN</text>
    <path d="M1197 385 1850 238v45l-653 127Z" fill="#345442" />
    <text x="1360" y="377" fontSize="19" letterSpacing="2" fill="#eee3c4" transform="rotate(-12 1360 377)">DAILY ESSENTIALS</text>
    {/* Low display creates a foreground scale cue without blocking the aisle. */}
    <g transform={compact ? "translate(235 300)" : undefined}>
      <path d="m80 854 262-49 159 77-260 61Z" fill="#665c45" />
      <path d="m80 854 161 89v177L80 1026Z" fill="#9e7d56" />
      <path d="m241 943 260-61v155l-260 83Z" fill="#b29569" />
      <path d="m92 865 147 66 249-49-146-60Z" fill="#4e624b" />
      {Array.from({ length: 30 }, (_, index) => <g key={index} transform={`translate(${132 + (index % 6) * 46 + Math.floor(index / 6) * 8 + (index * 7 % 13)} ${857 + Math.floor(index / 6) * 12 - (index % 6) * 6})`}>
        <ellipse rx={index % 3 === 0 ? 17 : 19} ry="14" fill={index % 3 === 0 ? "#b87d46" : index % 3 === 1 ? "#93a571" : "#c3aa59"} />
        <path d="m0-13 3-5" stroke="#596747" strokeWidth="3" /><ellipse cx="-7" cy="-5" rx="6" ry="3" fill="#fff0bc" opacity=".18" />
      </g>)}
      <path d="m241 943 260-61" stroke="#d5b78a" strokeWidth="7" />
      <path d="m95 894 126 63m35 21 230-64" stroke="#82694b" strokeWidth="4" opacity=".5" />
      <path d="m80 854 161 89v177L80 1026Z" fill={`url(#${prefix}-grain)`} />
    </g>
    <Checkout prefix={prefix} compact={compact} />
    <rect x="-700" y="-300" width="3200" height="2100" fill={`url(#${prefix}-edge)`} />
  </svg>;
});

// Retained as the rejected first study; not imported by the Customer experience.
export const ReimaginedIllustratedGroceryRoom = memo(function ReimaginedIllustratedGroceryRoom() {
  return <div className="reimagined-room grocery-room" aria-hidden="true" data-environment-study="grocery-v2">
    <div className="grocery-room-camera"><GroceryDrawing /><GroceryDrawing compact /></div>
    <div className="grocery-room-atmosphere" />
  </div>;
});
