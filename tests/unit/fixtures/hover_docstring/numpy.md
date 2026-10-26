<!-- polars 2.1.0, pyrefly 1.4.0 hover, corpus polars__DataFrame.filter.md:16-26 -->
Parameters  
----------  
predicates  
&nbsp;&nbsp;&nbsp;&nbsp;Expression(s) that evaluate to a boolean Series.  
constraints  
&nbsp;&nbsp;&nbsp;&nbsp;Column filters; use `name = value` to filter columns by the supplied value.  
&nbsp;&nbsp;&nbsp;&nbsp;Each constraint will behave the same as `pl.col(name).eq(value)`, and  
&nbsp;&nbsp;&nbsp;&nbsp;be implicitly joined with the other filter conditions using `&`.  
  
Notes  
-----  