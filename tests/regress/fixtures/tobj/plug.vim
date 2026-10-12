" A vim script file
let g:x = 1

lua << EOF
local function hello(name, greeting)
  if name then return greeting .. name end
end
EOF

function! Foo(a, b)
  return a:a + a:b
endfunction
