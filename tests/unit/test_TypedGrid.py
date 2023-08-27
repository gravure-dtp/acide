class test_TypedGrid:
    def test_new_none_shape(self):
        tg = TypedGrid("")
        print(tg, "\n")

    def test_new(self):
        tg = TypedGrid("", (5, 8))
        print(tg, "\n")

    def test_slicing(self)
        print(tg[2], "\n")
        print(tg[:,2:3], "\n")
        print(tg[:,2], "\n")
        print(tg[...,2], "\n")
        print(tg[...,7], "\n")
        print(tg[...,18], "\n")
        print(tg[9], "\n")
        # print(tg[9, 18], "\n")
        print(tg[2:5], "\n")
        print(tg[2:5, ...], "\n")
        print(tg[2:5, 3:-2], "\n")
        print(tg[:,3:-2], "\n")
        print(tg[2:3, 3:4], "\n")
        print(tg[2,5], "\n")
        sl = tg[3:5,3:8]
        print(sl, "\n")
        print(sl[1:,2:], "\n")

    def test_setitem(self):
        # assigning
        tg[3,4] = "hello"
        sl[0,0] = "goodbye"
        print(tg, "\n")
        # tg[3,5] = 3

    def test_getitem(self):
        # getting out of range
        print("[-2, -5]: ", tg[-2, -5])
        # print("[-2, -12]: ", tg[-2, -12])
        # print("[3, 9]: ", sl[3, 9])

    def test_iter(self):
        # iter
        print(sl, "\n")
        for item in sl:
            print(item)

    def test_contains(self):
        # contains
        print("goodbye" in tg)
        print(None in tg)
        print("adios" in tg)

