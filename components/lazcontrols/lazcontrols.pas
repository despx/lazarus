{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit LazControls;

interface

uses
  DividerBevel, ExtendedNotebook, ListFilterEdit, TreeFilterEdit, 
  ShortPathEdit, LvlGraphCtrl, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('DividerBevel', @DividerBevel.Register);
  RegisterUnit('ExtendedNotebook', @ExtendedNotebook.Register);
  RegisterUnit('ListFilterEdit', @ListFilterEdit.Register);
  RegisterUnit('TreeFilterEdit', @TreeFilterEdit.Register);
  RegisterUnit('ShortPathEdit', @ShortPathEdit.Register);
  RegisterUnit('LvlGraphCtrl', @LvlGraphCtrl.Register);
end;

initialization
  RegisterPackage('LazControls', @Register);
end.
