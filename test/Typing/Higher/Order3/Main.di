-- Imports

-- Pragmas

-- Infix

-- Data

-- Effects

-- Regions

-- Classes

-- Class dictionaries

-- Class instances

-- Foreign imports

-- Binds
foreign import extern succ
        :: forall %r0
        .  Base.Int %r0 -(!e0)> Base.Int %r0
        :- !e0        = Base.!Read %r0
        :$ Base.Data -> Base.Data;
        
foreign import extern danio
        :: forall t0 %r0 !e0 $c0
        .  (Base.Int %r0 -(!e0 $c0)> t0) -(!e0)> t0
        :$ Base.Thunk -> Base.Obj;
        
foreign import extern perch
        :: forall %r0 %r1 !e0 !e1 $c0 $c1
        .  ((Base.Int %r1 -(!e1 $c0)> Base.Int %r1) -(!e0 $c1)> Base.Int %r0) -(!e2)> Base.Int %r0
        :- !e2        = !{!e0; Base.!Read %r0}
        ,  !e1        :> Base.!Read %r1
        :$ Base.Thunk -> Base.Data;
        
foreign import extern appDanio
        :: forall t0 t1 %r0 !e0 !e1 $c0 $c1 $c2
        .  (((Base.Int %r0 -(!e1 $c0)> t1) -(!e1 $c1)> t1) -(!e0 $c2)> t0) -(!e0)> t0
        :$ Base.Thunk -> Base.Obj;
        
foreign import extern main
        :: Base.Unit -(!e0)> Base.Unit
        :- !e0        = System.Console.!Console
        :$ Base.Data -> Base.Data;
        

