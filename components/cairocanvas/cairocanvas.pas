unit CairoCanvas;

{$mode objfpc}{$H+}

{$define pangocairo}
{-$define breaklines}   // disabled as it's not UTF-8 safe

interface

uses
  Types, SysUtils, Classes, LCLType, LCLProc, Graphics, math, GraphMath,
  Printers, Cairo
  {$ifdef pangocairo}
  ,Pango, PangoCairo, GLib2
  {$endif}
  ;

type
  { TCairoPrinterCanvas }

  TCairoPrinterCanvas = class(TFilePrinterCanvas)
  private
    FLazClipRect: TRect;
    FUserClipRect: Pcairo_rectangle_t;
    {$ifdef pangocairo}
    fFontDesc: PPangoFontDescription;
    fFontDescStr: string;
    function StylesToStr(Styles: TFontStyles):string;
    {$endif}
    procedure SelectFontEx(AStyle: TFontStyles; const AName: string;
      ASize: double);
    function SX(x: double): double;
    function SY(y: double): double;
    function SX2(x: double): double;
    function SY2(y: double): double;
    procedure SetSourceColor(Color: TColor);
    procedure SetPenProperties;
    procedure SetBrushProperties;
    procedure SelectFont;
    procedure PolylinePath(Points: PPoint; NumPts: Integer);
    procedure EllipseArcPath(CX, CY, RX, RY: Double; Angle1, Angle2: Double;
      Clockwise, Continuous: Boolean);
    procedure ArcPath(ALeft, ATop, ARight, ABottom, Angle16Deg, Angle16DegLength: double);
    procedure ArcPath(ALeft, ATop, ARight, ABottom, StX, StY, EX, EY: double);
    procedure FillAndStroke;
    procedure FillOnly;
    procedure StrokeOnly;
    procedure TColorToRGB(Color: TColor; out R,G,B: double);
    // debug tools
    procedure DrawPoint(x,y: double; color: TColor);
    procedure DrawRefRect(x,y,awidth,aheight: double; color:TColor);
    procedure DebugSys;
  protected
    cr: Pcairo_t;
    ScaleX, ScaleY, FontScale: Double;
    procedure DoLineTo(X1,Y1: Integer); override;
    procedure CreateCairoHandle(BaseHandle: HDC); virtual;
    procedure DestroyCairoHandle; virtual;
    procedure SetHandle(NewHandle: HDC); override;
    procedure BeginDoc; override;
    procedure EndDoc; override;
    procedure NewPage; override;
    procedure CreateBrush; override;
    function GetClipRect: TRect; override;
    procedure SetClipRect(const ARect: TRect); override;
    function GetClipping: Boolean; override;
    procedure SetClipping(const AValue: boolean); override;
  public
    SurfaceXDPI, SurfaceYDPI: Integer;
    constructor Create(APrinter : TPrinter); override;
    constructor Create; overload;
    destructor Destroy; override;
    procedure FillRect(const ARect: TRect); override;
    procedure Rectangle(X1,Y1,X2,Y2: Integer); override;
    procedure Polyline(Points: PPoint; NumPts: Integer); override;
    procedure Polygon(Points: PPoint; NumPts: Integer; Winding: boolean = False); override;
    procedure FrameRect(const ARect: TRect); override;
    procedure Frame(const ARect: TRect); override;
    procedure RoundRect(X1, Y1, X2, Y2: Integer; RX, RY: Integer); override;
    procedure Ellipse(X1, Y1, X2, Y2: Integer); override;
    procedure Arc(ALeft, ATop, ARight, ABottom, Angle16Deg, Angle16DegLength: Integer); override;
    procedure Arc(ALeft, ATop, ARight, ABottom, StX, StY, EX, EY: Integer); override;
    procedure Chord(X1, Y1, X2, Y2, Angle1, Angle2: Integer); override;
    procedure Chord(X1, Y1, X2, Y2, StX, StY, EX, EY: Integer); override;
    procedure Pie(EllipseX1, EllipseY1, EllipseX2, EllipseY2, StartX, StartY, EndX, EndY: Integer); override;
    procedure RadialPie(Left, Top, Right, Bottom, Angle1, Angle2: Integer); override;
    procedure PolyBezier(Points: PPoint; NumPts: Integer; Filled: boolean = False; Continuous: boolean = False); override;
    procedure TextOut(X,Y: Integer; const Text: String); override;
    procedure TextRect(ARect: TRect; X1, Y1: integer; const Text: string; const Style: TTextStyle); override;
    function TextExtent(const Text: string): TSize; override;
    function GetTextMetrics(out M: TLCLTextMetric): boolean; override;
    procedure StretchDraw(const DestRect: TRect; SrcGraphic: TGraphic); override;
    procedure SetPixel(X,Y: Integer; Value: TColor); override;
{  Not implemented
    procedure FloodFill(X, Y: Integer; FillColor: TColor; FillStyle: TFillStyle); override;
    procedure CopyRect(const Dest: TRect; SrcCanvas: TCanvas; const Source: TRect); override;
    procedure Frame3d(var ARect: TRect; const FrameWidth: integer; const Style: TGraphicsBevelCut); override;}
  end;

  { TCairoFileCanvas }

  TCairoFileCanvas = class (TCairoPrinterCanvas)
  protected
    sf: Pcairo_surface_t;
    procedure CreateHandle; override;
    procedure DestroyCairoHandle; override;
  end;

  { TCairoPdfCanvas }

  TCairoPdfCanvas = class(TCairoFileCanvas)
  protected
    procedure CreateCairoHandle(BaseHandle: HDC); override;
  end;

  { TCairoSvgCanvas }

  TCairoSvgCanvas = class(TCairoFileCanvas)
  protected
    procedure CreateCairoHandle(BaseHandle: HDC); override;
  end;

  { TCairoPngCanvas }

  TCairoPngCanvas = class(TCairoFileCanvas)
  protected
    procedure CreateCairoHandle(BaseHandle: HDC); override;
    procedure DestroyCairoHandle; override;
  public
    constructor Create(APrinter: TPrinter); override;
  end;

  { TCairoPsCanvas }

  TCairoPsCanvas = class(TCairoFileCanvas)
  protected
    procedure CreateCairoHandle(BaseHandle: HDC); override;
  end;

implementation

uses
  IntfGraphics, GraphType, FPimage;

{ TCairoPrinterCanvas }

const
  Dash_Dash: array [0..2] of double = (3, 1, 3); //_ _
  Dash_Dot: array [0..1] of double = (1, 1); //. .
  Dash_DashDot: array [0..4] of double = (3, 1, 1, 1, 3); //_ . _
  Dash_DashDotDot: array [0..6] of double = (3, 1, 1, 1, 1, 1, 3); //_ . . _

procedure TCairoPrinterCanvas.SetPenProperties;

  procedure SetDash(d: array of double);
  var
    i, w: integer;
  begin
    w := Pen.Width;
    for i := 0 to High(d) do
      d[i] := d[i] * w;
    cairo_set_dash(cr, @d, High(d), 0);
  end;
begin
  SetSourceColor(Pen.Color);
(*  case Pen.Mode of
    pmBlack: begin
      SetSourceColor(clBlack);
      cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    end;
    pmWhite: begin
      SetSourceColor(clWhite);
      cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    end;
    pmCopy: cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    pmXor: cairo_set_operator(cr, CAIRO_OPERATOR_XOR);
    pmNotXor: cairo_set_operator(cr, CAIRO_OPERATOR_XOR);
{    pmNop,
    pmNot,
    pmCopy,
    pmNotCopy,
    pmMergePenNot,
    pmMaskPenNot,
    pmMergeNotPen,
    pmMaskNotPen,
    pmMerge,
    pmNotMerge,
    pmMask,
    pmNotMask,}
  else
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
  end;*)
  case Pen.Style of
    psSolid: cairo_set_dash(cr, nil, 0, 0);
    psDash: SetDash(Dash_Dash);
    psDot: SetDash(Dash_Dot);
    psDashDot: SetDash(Dash_DashDot);
    psDashDotDot: SetDash(Dash_DashDotDot);
  else
    cairo_set_dash(cr, nil, 0, 0);
  end;
  case Pen.EndCap of
    pecRound: cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    pecSquare: cairo_set_line_cap(cr, CAIRO_LINE_CAP_SQUARE);
    pecFlat: cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT);
  end;
  case Pen.JoinStyle of
    pjsRound: cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    pjsBevel: cairo_set_line_join(cr, CAIRO_LINE_JOIN_BEVEL);
    pjsMiter: cairo_set_line_join(cr, CAIRO_LINE_JOIN_MITER);
  end;

  cairo_set_line_width(cr, Pen.Width*72/XDPI); //line_width is diameter of the pen circle
end;

procedure TCairoPrinterCanvas.SetBrushProperties;
begin
  SetSourceColor(Brush.Color);
{  case Brush.Style of
    bsSolid
    bsClear
    bsHorizontal
    bsVertical
    bsFDiagonal
    bsBDiagonal
    bsCross
    bsDiagCross
    bsImage
    bsPattern
  end;}
end;

procedure TCairoPrinterCanvas.DoLineTo(X1, Y1: Integer);
begin
  cairo_move_to(cr, SX(PenPos.X), SY(PenPos.Y));
  inherited DoLineTo(X1, Y1);
  cairo_line_to(cr, SX(X1), SY(Y1));
  StrokeOnly;
end;

procedure TCairoPrinterCanvas.CreateCairoHandle(BaseHandle: HDC);
begin
  ScaleX := SurfaceXDPI/XDPI; //DPI can be changed between Create and CreateCairoHandle
  ScaleY := SurfaceYDPI/YDPI;
end;

procedure TCairoPrinterCanvas.DestroyCairoHandle;
begin
  cairo_destroy(cr);
  cr := nil;
end;

procedure TCairoPrinterCanvas.SetHandle(NewHandle: HDC);
begin
  if Assigned(cr) then
    DestroyCairoHandle;
  inherited SetHandle(NewHandle);
  if NewHandle <> 0 then
    CreateCairoHandle(NewHandle);
end;

procedure TCairoPrinterCanvas.BeginDoc;
begin
  inherited BeginDoc;
  if assigned(printer) then
    FLazClipRect:=printer.PaperSize.PaperRect.WorkRect;
end;

procedure TCairoPrinterCanvas.EndDoc;
begin
  inherited EndDoc;
  //if caller is printer, then at the end destroy cairo handles (flush output)
  //and establishes CreateCairoHandle call on the next print
  Handle := 0;
end;

procedure TCairoPrinterCanvas.NewPage;
begin
  inherited NewPage;
  cairo_show_page(cr);
end;

procedure TCairoPrinterCanvas.CreateBrush;
begin
end;

function TCairoPrinterCanvas.GetClipRect: TRect;
var
  x1,y1,x2,y2: double;
begin
  RequiredState([csHandleValid]);

  // it doesn't matter what the clip is in use, default or user
  // this returns always the current clip

  cairo_clip_extents(cr, @x1, @y1, @x2, @y2);
  result.Left:=round(x1/ScaleX);
  result.Top:=round(y1/ScaleY);
  result.Right:=round(x2/ScaleX);
  result.Bottom:=round(y2/ScaleY);
end;

procedure TCairoPrinterCanvas.SetClipRect(const ARect: TRect);
begin
  if FUserClipRect=nil then
    New(FUserClipRect);

  fUserClipRect^.x := SX(ARect.Left);
  fUserClipRect^.y := SY(ARect.Top);
  fUserClipRect^.width := SX2(ARect.Right-ARect.Left);
  fUserClipRect^.height:= SY2(ARect.Bottom-ARect.Top);

  cairo_reset_clip(cr);

  with fUserClipRect^ do
    cairo_rectangle(cr, x, y, width, Height);

  cairo_Clip(cr);
end;

function TCairoPrinterCanvas.GetClipping: Boolean;
begin
  result := (fUserClipRect<>nil);
end;

procedure TCairoPrinterCanvas.SetClipping(const AValue: boolean);
begin
  cairo_reset_clip(cr);

  if not AValue then begin
    // free user cliprect if exists
    if fUserClipRect<>nil then
      Dispose(fUserClipRect);
    fUserClipRect := nil;
  end
  else begin
    if fUserClipRect<>nil then
    begin
      with fUserClipRect^ do
      begin
        cairo_rectangle(cr, x, y, width, height);
        cairo_clip(cr);
      end;
    end else
      ; // cairo_reset_clip always clip
  end;
end;

procedure TCairoPrinterCanvas.DrawPoint(x, y: double; color: TColor);
var
  r,g,b: Double;
begin
  TColorToRGB(color, r, g, b);
  cairo_set_source_rgb(cr, r, g, b);
  cairo_rectangle(cr, x-2, y-2, 4, 4);
  cairo_fill(cr);
end;

procedure TCairoPrinterCanvas.DrawRefRect(x, y, awidth, aheight: double;
  color: TColor);
var
  r,g,b: double;
begin
  TColorToRGB(color, r, g, b);
  cairo_set_source_rgb(cr, r, g, b);
  cairo_rectangle(cr, x, y, awidth, aheight);
  cairo_move_to(cr, x, y);
  cairo_line_to(cr, x+awidth, y+aheight);
  cairo_move_to(cr, x+awidth, y);
  cairo_line_to(cr, x, y+aheight);
  cairo_stroke(cr);
end;

procedure TCairoPrinterCanvas.DebugSys;
var
  x,y: double;
  matrix: cairo_matrix_t;
begin
  cairo_get_current_point(cr, @x, @y);
  cairo_get_matrix(cr, @matrix);
  DebugLn('CurPoint:  x=%f y=%f',[x, y]);
  with matrix do
    DebugLn('CurMatrix: xx=%f yx=%f xy=%f yy=%f x0=%f y0=%f',[xx,yx,xy,yy,x0,y0]);
end;

constructor TCairoPrinterCanvas.Create(APrinter: TPrinter);
begin
  inherited Create(APrinter);
  ScaleX := 1;
  ScaleY := 1;
  FontScale := 1;
  SurfaceXDPI := 72;
  SurfaceYDPI := 72;
  XDPI := SurfaceXDPI;
  YDPI := SurfaceXDPI;
end;

constructor TCairoPrinterCanvas.Create;
begin
  Create(nil);
end;

destructor TCairoPrinterCanvas.Destroy;
begin
  if fUserClipRect<>nil then
    Dispose(fUserClipRect);
  fUserClipRect := nil;
  {$ifdef pangocairo}
  if fFontDesc<>nil then
    pango_font_description_free(fFontDesc);
  {$endif}
  inherited Destroy;
end;

function TCairoPrinterCanvas.SX(x: double): double;
begin
  Result := ScaleX*(x+FLazClipRect.Left);
end;

function TCairoPrinterCanvas.SY(y: double): double;
begin
  Result := ScaleY*(y+FLazClipRect.Top);
end;

function TCairoPrinterCanvas.SX2(x: double): double;
begin
  Result := ScaleX*x;
end;

function TCairoPrinterCanvas.SY2(y: double): double;
begin
  Result := ScaleY*y;
end;

procedure TCairoPrinterCanvas.SetSourceColor(Color: TColor);
var
  R, G, B: double;
begin
  //TColor je ve formatu BGR
  TColorToRGB(Color, R, G, B);
  cairo_set_source_rgb(cr, R, G, B);
end;

procedure TCairoPrinterCanvas.Rectangle(X1, Y1, X2, Y2: Integer);
begin
  Changing;
  RequiredState([csHandleValid, csBrushValid, csPenValid]);
  SetPenProperties;
  cairo_rectangle(cr, SX(X1), SY(Y1), SX2(X2-X1), SY2(Y2-Y1));
  FillAndStroke;
  Changed;
end;

//1 point rectangle in _Brush_ color
procedure TCairoPrinterCanvas.FrameRect(const ARect: TRect);
begin
  Changing;
  RequiredState([csHandleValid, csBrushValid]);
  cairo_rectangle(cr, SX(ARect.Left), SY(ARect.Top), SX2(ARect.Right-ARect.Left), SY2(ARect.Bottom-ARect.Top));
  SetSourceColor(Brush.Color);
  cairo_set_line_width(cr, 1);
  cairo_stroke(cr); //Don't touch
  Changed;
end;

procedure TCairoPrinterCanvas.Frame(const ARect: TRect);
begin
  Changing;
  RequiredState([csHandleValid, csPenValid]);
  cairo_rectangle(cr, SX(ARect.Left), SY(ARect.Top), SX2(ARect.Right-ARect.Left), SY2(ARect.Bottom-ARect.Top));
  cairo_set_line_width(cr, 1);
  SetSourceColor(Pen.Color);
  cairo_stroke(cr); //Don't touch
  Changed;
end;

//C* - center, R* - halfaxis
procedure TCairoPrinterCanvas.EllipseArcPath(CX, CY, RX, RY: Double; Angle1, Angle2: Double; Clockwise, Continuous: Boolean);
begin
  if (RX=0) or (RY=0) then //cairo_scale do not likes zero params
    Exit;
  cairo_save(cr);
  try
    cairo_translate(cr, SX(CX), SY(CY));
    cairo_scale(cr, SX2(RX), SY2(RY));
    if not Continuous then
      cairo_move_to(cr, cos(Angle1), sin(Angle1)); //Move to arcs starting point
    if Clockwise then
      cairo_arc(cr, 0, 0, 1, Angle1, Angle2)
    else
    cairo_arc_negative(cr, 0, 0, 1, Angle1, Angle2);
  finally
    cairo_restore(cr);
  end;
end;

procedure TCairoPrinterCanvas.FillOnly;
begin
  if Brush.Style <> bsClear then begin
    SetBrushProperties;
    cairo_fill(cr);
  end;
end;

procedure TCairoPrinterCanvas.StrokeOnly;
begin
  if Pen.Style <> psClear then begin
    SetPenProperties;
    cairo_stroke(cr);
  end;
end;

procedure TCairoPrinterCanvas.TColorToRGB(Color: TColor; out R, G, B: double);
begin
  R := (Color and $FF) / 255;
  G := ((Color shr 8) and $FF) / 255;
  B := ((Color shr 16) and $FF) / 255;
end;


{$ifdef pangocairo}
function TCairoPrinterCanvas.StylesToStr(Styles: TFontStyles): string;
begin
  Result := '';
  if fsBold in Styles then
    Result := Result + 'bold ';
  if fsItalic in Styles then
    Result := Result + 'italic ';
end;
{$endif}

procedure TCairoPrinterCanvas.FillAndStroke;
begin
  if Brush.Style <> bsClear then begin
    SetBrushProperties;
    if Pen.Style = psClear then
      cairo_fill(cr)
    else
      cairo_fill_preserve(cr);
  end;
  if Pen.Style <> psClear then begin
    SetPenProperties;
    cairo_stroke(cr);
  end;
end;

procedure TCairoPrinterCanvas.RoundRect(X1, Y1, X2, Y2: Integer; RX, RY: Integer);
begin
  Changing;
  RequiredState([csHandleValid, csPenValid, csBrushValid]);
  cairo_move_to(cr, SX(X1+RX), SY(Y1));
  cairo_line_to(cr, SX(X2-RX), SY(Y1));
  EllipseArcPath(X2-RX, Y1+RY, RX, RY, -PI/2, 0, True, True);
  cairo_line_to(cr, SX(X2), SY(Y2-RY));
  EllipseArcPath(X2-RX, Y2-RY, RX, RY, 0, PI/2, True, True);
  cairo_line_to(cr, SX(X1+RX), SY(Y2));
  EllipseArcPath(X1+RX, Y2-RY, RX, RY, PI/2, PI, True, True);
  cairo_line_to(cr, SX(X1), SY(Y1+RX));
  EllipseArcPath(X1+RX, Y1+RY, RX, RY, PI, PI*1.5, True, True);
  FillAndStroke;
  Changed;
end;

procedure TCairoPrinterCanvas.Ellipse(X1, Y1, X2, Y2: Integer);
begin
  Changing;
  RequiredState([csHandleValid, csPenValid, csBrushValid]);
  EllipseArcPath((X2+X1)/2, (Y2+Y1)/2, (X2-X1)/2, (Y2-Y1)/2, 0, 2*PI, True, False);
  FillAndStroke;
  Changed;
end;

procedure TCairoPrinterCanvas.Arc(ALeft, ATop, ARight, ABottom, Angle16Deg, Angle16DegLength: Integer);
begin
  Changing;
  RequiredState([csHandleValid, csPenValid]);
  ArcPath(ALeft, ATop, ARight, ABottom, Angle16Deg, Angle16DegLength);
  StrokeOnly;
  Changed;
end;

procedure TCairoPrinterCanvas.Chord(X1, Y1, X2, Y2, Angle1, Angle2: Integer);
begin
  Changing;
  RequiredState([csHandleValid, csPenValid, csBrushValid]);
  ArcPath(X1, Y1, X2, Y2, Angle1, Angle2);
  cairo_close_path(cr);
  FillAndStroke;
  Changed;
end;

procedure TCairoPrinterCanvas.RadialPie(Left, Top, Right, Bottom, Angle1, Angle2: Integer);
var
  cx, cy: double;
begin
  Changing;
  RequiredState([csHandleValid, csPenValid, csBrushValid]);
  ArcPath(Left, Top, Right, Bottom, Angle1, Angle2);
  cx := (Right+Left)/2;
  cy := (Bottom+Top)/2;
  cairo_line_to(cr, SX(cx), SY(cy));
  cairo_close_path(cr);
  FillAndStroke;
  Changed;
end;

procedure TCairoPrinterCanvas.ArcPath(ALeft, ATop, ARight, ABottom, Angle16Deg, Angle16DegLength: double);
var
  k: Double;
begin
  k := - 2*PI/(360*16);
  EllipseArcPath((ARight+ALeft)/2, (ABottom+ATop)/2, (ARight-ALeft)/2, (ABottom-ATop)/2,
    Angle16Deg*k, Angle16DegLength*k, False, False);
end;

procedure TCairoPrinterCanvas.Arc(ALeft, ATop, ARight, ABottom, StX, StY, EX, EY: Integer);
begin
  Changing;
  RequiredState([csHandleValid, csPenValid]);
  ArcPath(ALeft, ATop, ARight, ABottom, StX, StY, EX, EY);
  StrokeOnly;
  Changed;
end;

procedure TCairoPrinterCanvas.Chord(X1, Y1, X2, Y2, StX, StY, EX, EY: Integer);
begin
  Changing;
  RequiredState([csHandleValid, csPenValid, csBrushValid]);
  ArcPath(X1, Y1, X2, Y2, StX, StY, EX, EY);
  cairo_close_path(cr);
  FillAndStroke;
  Changed;
end;

procedure TCairoPrinterCanvas.Pie(EllipseX1, EllipseY1, EllipseX2, EllipseY2,
  StartX, StartY, EndX, EndY: Integer);
var
  cx, cy: double;
begin
  Changing;
  RequiredState([csHandleValid, csPenValid, csBrushValid]);
  ArcPath(EllipseX1, EllipseY1, EllipseX2, EllipseY2, StartX, StartY, EndX, EndY);
  cx := (EllipseX2+EllipseX1)/2;
  cy := (EllipseY2+EllipseY1)/2;
  cairo_line_to(cr, SX(cx), SY(cy));
  cairo_close_path(cr);
  FillAndStroke;
  Changed;
end;

procedure TCairoPrinterCanvas.ArcPath(ALeft, ATop, ARight, ABottom, StX, StY, EX, EY: double);

  function ATanInt(x, y: double): double;
  begin
    if x <> 0 then begin
      result := ArcTan(y/x);
      if x < 0 then
        result := result + PI;
    end else begin
      if y > 0 then
        result := PI/2
      else
        result := - PI/2;
    end;
  end;

var
  Angle1, Angle2: double;
  cx, cy: double;
begin
  cx := (ARight+ALeft)/2;
  cy := (ABottom+ATop)/2;
  Angle1 := ATanInt(StX-cx, StY-cy);
  Angle2 := ATanInt(EX-cx, EY-cy);
  EllipseArcPath(cx, cy, (ARight-ALeft)/2, (ABottom-ATop)/2, Angle1, Angle2, False, False);
end;

procedure TCairoPrinterCanvas.PolyBezier(Points: PPoint; NumPts: Integer; Filled: boolean; Continuous: boolean);
var
  p, ep: PPoint;
begin
  p := Points;
  ep := Points + NumPts;
  while p < ep do begin
    if (p = Points) or not Continuous then begin //First or non cont.
      cairo_move_to(cr, SX(p^.X), SY(p^.Y));
      inc(p);
    end;
    cairo_curve_to(cr, SX(p^.X), SY(p^.Y), SX((p+1)^.X), SY((p+1)^.Y), SX((p+2)^.X), SY((p+2)^.Y));
    inc(p, 3);
  end;
  if Filled then begin
    cairo_close_path(cr);
    FillAndStroke;
  end else
    StrokeOnly;
end;

//Toy interface
procedure TCairoPrinterCanvas.SelectFont;
begin
  RequiredState([csHandleValid]);
  SelectFontEx(Font.Style, Font.Name, abs(Font.Size));
  SetSourceColor(Font.Color);
end;

procedure TCairoPrinterCanvas.SelectFontEx(AStyle: TFontStyles; const AName: string; ASize: double);
var
  slant: cairo_font_slant_t;
  weight: cairo_font_weight_t;
  {$ifdef pangocairo}
  S: string;
  {$endif}
begin
  if fsBold in Font.Style then
    weight := CAIRO_FONT_WEIGHT_BOLD
  else
    weight := CAIRO_FONT_WEIGHT_NORMAL;
  if fsItalic in Font.Style then
    slant := CAIRO_FONT_SLANT_ITALIC
  else
    slant := CAIRO_FONT_SLANT_NORMAL;
  {$ifdef pangocairo}
  S := format('%s %s %dpx',[AName, StylesToStr(AStyle), round(ASize)]);
  if (fFontDesc=nil) or (S<>fFontDescStr) then
  begin
    if fFontDesc<>nil then
      pango_font_description_free(fFontDesc);
    fFontDesc := pango_font_description_from_string(pchar(s));
  end;
  fFontDescStr := s;
  {$endif}
  cairo_select_font_face(cr, PChar(AName), slant, weight);
  cairo_set_font_size(cr, ASize*FontScale)
end;

procedure TCairoPrinterCanvas.TextOut(X, Y: Integer; const Text: String);
var
  e: cairo_font_extents_t;
  {$ifdef pangocairo}
  Layout: PPangoLayout;
  {$endif}
begin
  Changing;
  RequiredState([csHandleValid, csFontValid, csBrushValid]);
  SelectFont;
  cairo_font_extents(cr, @e);
  cairo_save(cr);
  {$ifdef pangocairo}
  // use absolute font size sintax  (px)
  Layout := Pango_Cairo_Create_Layout(cr);
  pango_layout_set_font_description(layout, fFontDesc);
  {$endif}
  if Font.Orientation = 0 then
  begin
    cairo_move_to(cr, SX(X), SY(Y)+e.ascent);
    {$ifdef pangocairo}
    //DebugLn('TextOut ',Text);
    //DebugSys;
    pango_layout_set_text(layout, PChar(Text), -1);
    {$else}
    cairo_show_text(cr, PChar(Text)); //Reference point is on the base line
    {$endif}
  end
  else
  begin
    cairo_move_to(cr, SX(X)+e.ascent, SY(Y));
    cairo_rotate(cr, -gradtorad(Font.Orientation));
    {$ifdef pangocairo}
    pango_layout_set_text(layout, PChar(Text), -1);
    {$else}
    cairo_show_text(cr, PChar(Text)); //Reference point is on the base line
    {$endif}
  end;
  {$ifdef pangocairo}
  pango_cairo_update_layout(cr, layout);
  // get the same text origin as cairo_show_text (baseline left, instead of Pango's top left)
  pango_cairo_show_layout_line (cr, pango_layout_get_line (layout, 0));
  g_object_unref(layout);
  {$endif}
  cairo_restore(cr);
  Changed;
end;

type
  TLine = class
    Start, EndL: Integer;
    Width: Double;
  end;

procedure TCairoPrinterCanvas.TextRect(ARect: TRect; X1, Y1: integer; const Text: string; const Style: TTextStyle);
var
  te: cairo_text_extents_t;
  s: string;
{$ifdef breaklines}
  Lines: TList;
  CurLine: TLine;
  len: integer;
  LastBreakEndL: Integer;
  LastBreakStart: Integer;

  procedure BreakLine(en, st: Integer);
  var
    s1: string;
    te: cairo_text_extents_t;
  begin
    if en>=0 then begin
      if en>1 then begin
        if en <= len then
          CurLine.EndL := en
        else
          CurLine.EndL := len;
      end else
        CurLine.EndL := 1;
      s1 := Copy(s, CurLine.Start, CurLine.EndL-CurLine.Start+1);
      cairo_text_extents(cr, PChar(s1), @te);
      CurLine.Width := te.width + te.x_bearing;
    end;
    if st > 0 then begin
      CurLine := TLine.Create;
      Lines.Add(CurLine);
      if st <= len then
        CurLine.Start := st
      else
        CurLine.Start := len;
      CurLine.EndL := 0;
    end;
    LastBreakEndL := 0;
    LastBreakStart := 0;
  end;
{$endif}

var
  fe: cairo_font_extents_t;
  fd: TFontData;
  s1, ch: string;
  i, j: integer;
  BoxLeft, BoxTop, BoxWidth, BoxHeight: Double;
  StartLeft, StartTop: Double;
  BreakBoxWidth: Double;
  x, y: Double;
  r,b: double;
  {$ifdef pangocairo}
  Layout: PPangoLayout;
  ink,logical: TPangoRectangle;
  {$endif}

  {$ifndef breaklines}
  Lines: TStringList;
  {$endif}
begin
  Changing;
  RequiredState([csHandleValid, csFontValid, csBrushValid]);
  cairo_save(cr);
  try
    s := Text;
    BoxWidth := SX2(ARect.Right-ARect.Left);
    BoxHeight := SY2(ARect.Bottom-ARect.Top);
    BoxLeft := SX(ARect.Left);
    BoxTop := SY(ARect.Top);
    StartLeft := SX(X1);
    StartTop := SY(Y1);
    //DebugLn('Box= l=%f t=%f',[BoxLeft,BoxTop]);
    //DebugLn('     x=%f y=%f',[StartLeft,StartTop]);
    if Style.Alignment = taLeftJustify then
      BreakBoxWidth := SX(ARect.Right - X1)
    else
      BreakBoxWidth := BoxWidth;

    if Style.Clipping then begin
      r := BoxWidth+Pen.Width;
      b := BoxHeight+Pen.Width;

      //DrawPoint(boxLeft, boxTop, clRed);
      //DrawPoint(boxLeft+r, boxTop+b, clBlue);
      //DrawRefRect(boxLeft, boxTop, r, b, clGreen);

      cairo_rectangle(cr, BoxLeft, BoxTop, r, b);
      cairo_clip(cr);
    end;

    if (Font.Orientation=900) or (Font.Orientation=2700) then begin
      x := BoxWidth;
      BoxWidth := BoxHeight;
      BoxHeight := x;
    end;

    if Style.ExpandTabs then
      s := StringReplace(s, #9, '        ', [rfReplaceAll])
    else
      s := StringReplace(s, #9, ' ', [rfReplaceAll]);

    if Style.SingleLine then begin
      s := StringReplace(s, #13+#10, ' ', [rfReplaceAll]);
      s := StringReplace(s, #13, ' ', [rfReplaceAll]);
      s := StringReplace(s, #10, ' ', [rfReplaceAll]);
    end;

    if Style.Opaque then begin
      SetSourceColor(Brush.Color);
      cairo_rectangle(cr, BoxLeft, BoxTop, BoxWidth, BoxHeight);
      cairo_fill(cr)
    end;

    if Style.SystemFont and Assigned(OnGetSystemFont) then begin
      fd := GetFontData(OnGetSystemFont());
      SelectFontEx(fd.Style, fd.Name, fd.Height);
      SetSourceColor(clWindowText);
    end else
      SelectFont;

    {$ifdef pangocairo}
    Layout := Pango_Cairo_Create_Layout(cr);
    pango_layout_set_font_description(layout, fFontDesc);
    {$else}
    cairo_font_extents(cr, @fe);
    {$endif}

    {$ifdef breaklines}
    Lines := TList.Create;
    //Break lines
    len := Length(s);
    BreakLine(-1, 1);
    i := 1;
    while i<=len+1 do begin
      if i<=len then
        ch := s[i]
      else
        ch := '';
      //CR LF breaking
      if ch = #13 then begin
        if (i < len) and (s[i+1] = #10) then begin
          BreakLine(i-1, i+2);
          inc(i, 2);
          Continue;
        end else begin
          BreakLine(i-1, i+1);
          inc(i, 1);
          Continue;
        end;
      end;
      if ch = #10 then begin
        BreakLine(i-1, i+1);
        inc(i, 1);
        Continue;
      end;

      //Word breaking
      if Style.Wordbreak then begin
        if (ch = '') or (ch = ' ') then begin //'' last char
          s1 := Copy(s, CurLine.Start, i-CurLine.Start);
          {$ifdef pangocairo}
          {$else}
          cairo_text_extents(cr, PChar(s1), @te);
          {$endif}
          //skip following break chars
          j := i+1;
          while (j<=len) and (s[j] = ' ') do
            inc(j);
          if (te.width+te.x_bearing) <= BreakBoxWidth then begin
            LastBreakEndL := i-1;
            LastBreakStart := j;
          end else begin //overflow
            if LastBreakEndL<=0 then begin //cannot break
              BreakLine(i-1, j);
              inc(i);
              Continue;
            end else begin
              i := LastBreakStart; //before BreakLine where is LastBreakStart changed
              BreakLine(LastBreakEndL, LastBreakStart);
              Continue;
            end;
          end;
        end;
      end;

      //next char
      inc(i);
    end;
    //Close last CurLine
    BreakLine(Len, -1);

    {$else breaklines}

    Lines := TStringList.Create;
    Lines.Text := s;

    {$endif}

    {$ifdef pangocairo}
    // TODO: missing breaklines
    pango_layout_set_text(layout, pchar(s), -1);
    pango_layout_get_extents(Layout, @ink, @logical);
    //Calc start 'box' relative positions
    case Style.Layout of
      tlTop:    y := 0;
      tlCenter: y := BoxHeight/2 - logical.Height/PANGO_SCALE/2;
      tlBottom: y := BoxHeight - logical.height/PANGO_SCALE;
    end;
    {$else}
    //Calc start positions
    case Style.Layout of
      tlTop:    y := 0;
      tlCenter: y := BoxHeight/2 - fe.height*Lines.Count/2;
      tlBottom: y := BoxHeight - fe.height*Lines.Count;
    end;
    {$endif}

    // translate origin
    cairo_translate(cr, StartLeft, StartTop);
    // rotate
    cairo_rotate(cr, -DegToRad(Font.Orientation/10));

    //Text output
    for i := 0 to Lines.Count-1 do begin

      {$ifdef breaklines}
      CurLine := TLine(Lines.Items[i]);
      s1 := Copy(s, CurLine.Start, CurLine.EndL-CurLine.Start+1);
      {$else}
      s1 := Lines[i];
      {$endif}

      //DebugLn('i=%i y=%f s1=%s',[i,y,s1]);
      {$ifdef pangocairo}
      pango_layout_set_text(layout, pchar(s1), -1);
      pango_layout_get_extents(Layout, @ink, @logical);
      case Style.Alignment of
        taLeftJustify:  x := 0;
        taCenter:       x := BoxWidth/2 - logical.width/PANGO_SCALE/2;
        taRightJustify: x := BoxWidth - logical.Width/PANGO_SCALE;
      end;
      cairo_move_to(cr, x, y);
      //DebugLn('TextRect ',S1);
      //DebugSys;
      pango_cairo_show_layout(cr, layout);
      y := y + logical.height/PANGO_SCALE;
      {$else}
      case Style.Alignment of
        taLeftJustify: x := StartLeft;
        taCenter: x := BoxLeft + BoxWidth/2 - CurLine.Width/2;
        taRightJustify: x := BoxLeft+BoxWidth - CurLine.Width;
      end;
      cairo_move_to(cr, x, y+fe.ascent);
      cairo_show_text(cr, PChar(s1)); //Reference point is on the base line
      y := y + fe.height;
      {$endif}
    end;
    {$ifdef pangocairo}
    g_object_unref(layout);
    {$endif}

  finally
    cairo_restore(cr);
    {$ifdef breaklines}
    for i := 0 to Lines.Count-1 do
      TLine(Lines.Items[i]).Free;
    {$endif}
    Lines.Free;
  end;
  Changed;
end;

function TCairoPrinterCanvas.TextExtent(const Text: string): TSize;
var
  extents: cairo_text_extents_t;
  {$ifdef pangocairo}
  Layout: PPangoLayout;
  theRect: TPangoRectangle;
  {$endif}
begin
  SelectFont;
  {$ifdef pangocairo}
  Layout := Pango_Cairo_Create_Layout(cr);
  pango_layout_set_font_description(Layout, fFontDesc);
  cairo_text_extents(cr, PChar(Text), @extents);
  pango_layout_set_text(Layout, pchar(Text), -1);
  pango_layout_get_extents(Layout, nil, @theRect);
  Result.cx := Round((theRect.width/PANGO_SCALE)/ScaleX);
  Result.cy := Round((theRect.height/PANGO_SCALE)/ScaleY);
  g_object_unref(Layout);
  {$else}
  cairo_text_extents(cr, PChar(Text), @extents); //transformation matrix is here ignored
  Result.cx := Round((extents.width)/ScaleX+extents.x_bearing);
  Result.cy := Round((extents.height)/ScaleY-extents.y_bearing);
  {$endif}
end;

function TCairoPrinterCanvas.GetTextMetrics(out M: TLCLTextMetric): boolean;
var
  e: cairo_font_extents_t;
begin
  SelectFont;
  cairo_font_extents(cr, @e); //transformation matrix is here ignored
  FillChar(M{%H-}, SizeOf(M), 0);
  M.Ascender := Round(e.ascent/ScaleY);
  M.Descender := Round(e.descent/ScaleY);
  M.Height := Round(e.height/ScaleY);
  Result := True;
end;

procedure TCairoPrinterCanvas.StretchDraw(const DestRect: TRect; SrcGraphic: TGraphic);

  function TranslateBufferByIntfImage(buf: PByte; W, H: Integer): Boolean;
  var
    p: PDWord;
    x, y: Integer;
    c: TFPColor;
    Img: TLazIntfImage;
  begin
    Img := TRasterImage(SrcGraphic).CreateIntfImage;
    try
      if Img.DataDescription.Format=ricfNone then begin
        Result := False;
        Exit;
      end;
      p := Pointer(buf);
      for y := 0 to H-1 do begin
        for x := 0 to W-1 do begin
          c := Img.Colors[x, y];
          p^ := Hi(c.alpha) shl 24 + Hi(c.red) shl 16 + Hi(c.green) shl 8 + Hi(c.blue);
          inc(p);
        end;
      end;
    finally
      Img.Free;
    end;
    Result := True;
  end;

var
  sf: Pcairo_surface_t;
  buf: PByte;
  W, H: Integer;
  SW, SH: Double;
begin
  if not (SrcGraphic is TRasterImage) then begin
    inherited StretchDraw(DestRect, SrcGraphic);
    Exit;
  end;

  Changing;
  RequiredState([csHandleValid]);
  W := SrcGraphic.Width;
  H := SrcGraphic.Height;

  buf := GetMem(W*H*4);
  try
    cairo_save(cr);
    //FillDWord(buf^, W*H, $00000000);
    if not TranslateBufferByIntfImage(buf, W, H) then
      Exit;

    sf := cairo_image_surface_create_for_data(buf, CAIRO_FORMAT_ARGB32, W, H, W*4);
    cairo_translate(cr, SX(DestRect.Left), SY(DestRect.Top));
    SW := (DestRect.Right - DestRect.Left)/W;
    SH := (DestRect.Bottom - DestRect.Top)/H;
    cairo_scale(cr, SX2(SW), SY2(SH));
    cairo_set_source_surface(cr, sf, 0, 0);
    cairo_paint(cr);
    cairo_surface_destroy(sf);
    cairo_restore(cr);
  finally
    FreeMem(buf);
  end;
  Changed;
end;

procedure TCairoPrinterCanvas.SetPixel(X, Y: Integer; Value: TColor);
begin
  Changing;
  RequiredState([csHandleValid, csPenValid]);
  SetSourceColor(Value);
  cairo_rectangle(cr, SX(X), SY(Y), 1, 1);
  cairo_fill(cr);
  Changed;
end;

procedure TCairoPrinterCanvas.PolylinePath(Points: PPoint; NumPts: Integer);
var
  p: PPoint;
  i: integer;
begin
  p := Points;
  cairo_move_to(cr, SX(p^.X), SY(p^.Y));
  for i := 0 to NumPts-2 do begin
    inc(p);
    cairo_line_to(cr, SX(p^.X), SY(p^.Y));
  end;
end;

procedure TCairoPrinterCanvas.Polyline(Points: PPoint; NumPts: Integer);
begin
  if NumPts <= 0 then
    Exit;
  Changing;
  RequiredState([csHandleValid, csPenValid]);
  PolylinePath(Points, NumPts);
  StrokeOnly;
  Changed;
end;

procedure TCairoPrinterCanvas.Polygon(Points: PPoint; NumPts: Integer; Winding: boolean);
begin
  if NumPts <= 0 then
    Exit;
  Changing;
  RequiredState([csHandleValid, csBrushValid, csPenValid]);
  PolylinePath(Points, NumPts);
  cairo_close_path(cr);
  FillAndStroke;
  Changed;
end;

procedure TCairoPrinterCanvas.FillRect(const ARect: TRect);
begin
  Changing;
  RequiredState([csHandleValid, csBrushValid]);
  cairo_rectangle(cr, SX(ARect.Left), SY(ARect.Top), SX2(ARect.Right-ARect.Left), SY2(ARect.Bottom-ARect.Top));
  FillOnly;
  Changed;
end;

{ TCairoFileCanvas }

procedure TCairoFileCanvas.CreateHandle;
begin
  Handle := 1; // set dummy handle (calls SetHandle)
end;

procedure TCairoFileCanvas.DestroyCairoHandle;
begin
  cairo_surface_finish(sf);
  cairo_surface_destroy(sf);
  sf := nil;
  inherited DestroyCairoHandle;
end;

{ TCairoPdfCanvas }

procedure TCairoPdfCanvas.CreateCairoHandle(BaseHandle: HDC);
begin
  inherited CreateCairoHandle(BaseHandle);
  //Sizes are in Points, 72DPI (1pt = 1/72")
  sf := cairo_pdf_surface_create(PChar(FOutputFileName), PaperWidth*ScaleX, PaperHeight*ScaleY);
  cr := cairo_create(sf);
end;

{ TCairoPsCanvas }

procedure TCairoPsCanvas.CreateCairoHandle(BaseHandle: HDC);
var
  s: string;
  W, H: Double;
begin
  inherited CreateCairoHandle(BaseHandle);

  if Orientation = poLandscape then begin
    s := '%%PageOrientation: Landscape';
    W := PaperHeight*ScaleY; //switch H, W
    H := PaperWidth*ScaleX;
  end else begin
    s := '%%PageOrientation: Portait';
    W := PaperWidth*ScaleX;
    H := PaperHeight*ScaleY;
  end;

  //Sizes are in Points, 72DPI (1pt = 1/72")
  sf := cairo_ps_surface_create(PChar(FOutputFileName), W, H);
  cr := cairo_create(sf);

  cairo_ps_surface_dsc_begin_setup(sf);
  cairo_ps_surface_dsc_comment(sf, PChar(s));

  if Orientation = poLandscape then begin //rotate and move
    cairo_translate(cr, 0, H);
    cairo_rotate(cr, -PI/2);
  end;
end;

{ TCairoSvgCanvas }

procedure TCairoSvgCanvas.CreateCairoHandle(BaseHandle: HDC);
begin
  inherited CreateCairoHandle(BaseHandle);
  //Sizes are in Points, 72DPI (1pt = 1/72")
  sf := cairo_svg_surface_create(PChar(FOutputFileName), PaperWidth*ScaleX, PaperHeight*ScaleY);
  cr := cairo_create(sf);
end;

{ TCairoPngCanvas }

constructor TCairoPngCanvas.Create(APrinter: TPrinter);
begin
  inherited Create(APrinter);
end;

procedure TCairoPngCanvas.CreateCairoHandle(BaseHandle: HDC);
begin
  inherited CreateCairoHandle(BaseHandle);
  //I do not know how to retrieve DPI of cairo_image_surface
  //It looks like that Cairo uses same DPI as Screen, but how much is it in case of console app???
  //You must set Surface?DPI externally. For example:
  //c := TCairoPngCanvas.Create;
  //c.SurfaceXDPI := GetDeviceCaps(DC, LOGPIXELSX);
  //c.SurfaceYDPI := GetDeviceCaps(DC, LOGPIXELSY);
  sf := cairo_image_surface_create(CAIRO_FORMAT_ARGB32, PaperWidth, PaperHeight);
  cr := cairo_create(sf);
  cairo_scale(cr, 1/ScaleX, 1/ScaleY);
end;

procedure TCairoPngCanvas.DestroyCairoHandle;
begin
  cairo_surface_write_to_png(sf, PChar(FOutputFileName));
  inherited DestroyCairoHandle;
end;

end.

