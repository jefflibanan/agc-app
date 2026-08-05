$path = 'C:\Users\User\OneDrive\Desktop\Claude\Event App\index.html'
$lines = [System.Collections.Generic.List[string]](Get-Content -Path $path -Encoding UTF8)

$startLine = 1011  # "const EVENTS = ["
$endLine   = 1070  # closing "}catch(e){}" of the second sync block
# sanity check before touching anything
if ($lines[$startLine-1] -notmatch '^const EVENTS = \[') { throw "start line mismatch: $($lines[$startLine-1])" }
if ($lines[$endLine-1] -ne '}catch(e){}') { throw "end line mismatch: $($lines[$endLine-1])" }

$replacement = @'
const EVENTS = [];
function fmtSold(n){
  if(!n) return String.fromCharCode(8212);
  if(n>=1000) return (n/1000).toFixed(n%1000>=100?1:0)+'K';
  return String(n);
}
function mapEventRow(row, sold){
  const d=new Date(row.event_date+'T00:00:00');
  return {
    id:row.id, b:row.brand_id, title:row.title,
    date:d.toLocaleDateString('en-US',{month:'short'})+' '+d.getDate(),
    mo:d.toLocaleDateString('en-US',{month:'short'}), da:String(d.getDate()),
    time:row.doors_time, venue:row.venue, price:row.price,
    feat:row.featured, booked:fmtSold(sold),
    about:row.description, img:row.image_url||null
  };
}
let seatCounts = {};
async function loadEventsFromSupabase(){
  const { data: rows, error } = await sb.from('events').select('*').order('id');
  if(error){ console.error('Failed to load events from Supabase', error); return; }
  try{
    const { data: counts } = await sb.rpc('get_event_seat_counts');
    seatCounts = {};
    (counts||[]).forEach(c=>{ seatCounts[c.event_id]=c.sold; });
  }catch(e){ console.error('seat counts failed', e); }
  EVENTS.length = 0;
  (rows||[]).filter(r=>!r.is_paused).forEach(r=>EVENTS.push(mapEventRow(r, seatCounts[r.id])));
}
'@ -split "`r?`n"

$before = $lines.GetRange(0, $startLine-1)
$after  = $lines.GetRange($endLine, $lines.Count - $endLine)

$out = New-Object System.Collections.Generic.List[string]
$out.AddRange($before)
$out.AddRange([string[]]$replacement)
$out.AddRange($after)

[IO.File]::WriteAllText($path, ($out -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
"done. old line count: $($lines.Count), new line count: $($out.Count)"
