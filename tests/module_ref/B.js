/*
 * @providesModule B
 * @flow
 */

declare function ifRequired<TModule, TYes>(
  id: $Flow$ModuleRef<TModule>,
  cbYes: (module: TModule) => TYes,
): TYes | void;

ifRequired('A', (A: any) => A.FOO); // Error - A is a plain string, not a module ref
ifRequired('m#A', A => A.BAR); // Error - BAR is not present in A's exports
ifRequired('m#A', A => A.FOO); // Ok
